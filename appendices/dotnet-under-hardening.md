# Appendix - .NET workloads under a hardened baseline

[← 08 - Dependencies & health](../act-3/stage-08.md) · [Walkthrough index](../README.md)

Stage 08's baseline (read-only root filesystem, non-root, dropped capabilities, `RuntimeDefault` seccomp, resource limits) shipped against this course's minimal API and nothing broke. This appendix is the catalogue for when your .NET workload isn't so minimal: what actually conflicts with each control, whether the fix is **app code**, **config**, or **a mount**, and the truth about runtime code generation.

## The codegen question, answered first

**JIT, `Reflection.Emit`, and the default serializers never touch the filesystem: they generate code *in memory*.** `System.Text.Json`'s reflection path, expression-tree compilation, even `XmlSerializer` on modern .NET all emit IL to memory, so **they do not break `readOnlyRootFilesystem`**. The folk memory that "serialization writes to disk" is real but belongs to .NET Framework: `XmlSerializer` there generated C# and shelled out to the compiler via temp files, and ASP.NET compiled pages into `Temporary ASP.NET Files`. .NET Core ended both.

What runtime codegen *does* interact with is stricter **execution** policy, not the filesystem: the JIT needs writable-then-executable memory pages. `RuntimeDefault` seccomp allows this (which is why stage 08 passed); environments banning executable memory (some gVisor/SELinux `execmem` setups) are where JIT itself dies.

**Eliminating runtime codegen is available today, not in .NET 11:** source generators moved serializer codegen to *compile time* in .NET 6 (`JsonSerializerContext`, `[GeneratedRegex]`), and **Native AOT has supported ASP.NET Core minimal APIs and gRPC since .NET 8**. No JIT at all, faster cold start, smaller attack surface. The honest boundary: MVC/Razor Pages are still not AOT-compatible as of .NET 10; .NET 11 (this November) keeps widening coverage rather than unlocking the feature. So: minimal APIs and gRPC services can go AOT now; MVC apps harden fine under JIT because JIT was never the filesystem problem.

## What actually writes to disk - and each one's fix

| Writer | When it bites | Fix (and where the fix lives) |
|---|---|---|
| **DataProtection key ring** (`~/.aspnet/DataProtection-Keys`) | Anything using auth cookies, antiforgery, TempData: the #1 real-world casualty. Symptom: "storing keys in a repository which is not persisted"; users logged out on every restart; antiforgery failures across replicas | **App config**: persist keys to a shared store, blob storage + Key Vault protection (`PersistKeysToAzureBlobStorage` + `ProtectKeysWithAzureKeyVault`). A mounted volume only works single-replica; multi-replica *requires* the shared store. This is config the workload should have anyway |
| **Multipart/form upload buffering** | Uploads past the 64KB memory threshold spool to `Path.GetTempPath()`; also `Request.EnableBuffering()` | **Mount**: the stage-08 escape hatch, `emptyDir` at `/tmp`. Optionally point `TMPDIR` at a dedicated mount to make the dependency explicit |
| **Diagnostics IPC socket** (`/tmp/dotnet-diagnostic-*`) | Created at startup; fails *non-fatally* on read-only root, but its absence silently breaks `dotnet-trace`/`dotnet-counters` attach | **Config**: either the `/tmp` mount (keeps tooling), or `DOTNET_EnableDiagnostics=0` (explicitly gives it up, arguably the harder posture) |
| **Crash dumps** | `createdump` writes where `DOTNET_DbgMiniDumpName` points (default temp), a read-only path means no dump exactly when you wanted one | **Config + mount**: `DOTNET_DbgEnableMiniDump=1`, `DOTNET_DbgMiniDumpName` onto a mounted path |
| **Single-file bundle extraction** | Single-file publishes that must extract (some native-lib layouts) unpack to `DOTNET_BundleExtractBaseDir` | **Config**: point it at a mount, or publish non-single-file in containers, where single-file buys nothing |
| **X509 user store** (`~/.dotnet/corefx/cryptography/x509stores`) | Code importing certs into `StoreLocation.CurrentUser` at runtime | **App code**: load certs from mounted Secrets/files instead of importing into a store |
| **Razor runtime compilation** | `AddRazorRuntimeCompilation`: a dev-loop feature that compiles views on the fly | **App config**: don't ship it; precompiled views are the production default anyway |
| **File logging** | Any logger writing local files | **App config**: console structured logs; the platform owns shipping (twelve-factor, and stage 09's stack is the reason) |

## The non-filesystem conflicts

- **Non-root**: ports below 1024 are gone; the official images already bind 8080 (`ASPNETCORE_HTTP_PORTS`) and ship the `app` user (UID 1654, .NET 8+), which is exactly what the baseline's `runAsUser` pins. Mounted cert/key files need `fsGroup`-compatible permissions.
- **Dropped capabilities**: nothing in a normal ASP.NET app needs any; raw sockets/ICMP would, and that's a design smell in an API service.
- **Resource limits**: .NET is container-aware; Server GC sizes its heap from the cgroup limit, and DATAS (.NET 8+, default in 9+) adapts it dynamically. Casualties show up under *tight* limits: set requests/limits honestly, and reach for `DOTNET_GCHeapHardLimitPercent` only with a measured reason.

## Shutdown: SIGTERM is a contract, SIGKILL is a deadline

Kubernetes never asks twice. On pod deletion (every rollout, every drain, every Reloader re-roll) the sequence is: the pod is removed from Service endpoints *concurrently* with the `preStop` hook, then **SIGTERM** goes to the container's PID 1, then after `terminationGracePeriodSeconds` (default 30s) comes **SIGKILL**, which no process can handle, by design. So "responding properly to SIGKILL" really means: making sure everything is finished before it arrives. The .NET host does the right thing with SIGTERM out of the box (`WebApplication`/Generic Host trigger graceful shutdown: stop accepting, drain in-flight requests, run `StopAsync` on hosted services). There are four classic ways to break that contract:

| Trap | What happens | Fix |
|---|---|---|
| **Shell-form ENTRYPOINT** (`ENTRYPOINT dotnet app.dll` or `sh -c ...`) | The shell is PID 1 and doesn't forward signals: the app *never sees* SIGTERM, serves nothing during the grace period, and dies by SIGKILL looking like a hang | Exec form: `ENTRYPOINT ["dotnet", "app.dll"]`. The official images do this; hand-rolled Dockerfiles are where it breaks |
| **The 5-second haircut** | The host's own `HostOptions.ShutdownTimeout` defaults to **5s**, well inside Kubernetes' 30s grace. In-flight requests and `StopAsync` work get cancelled at 5s even though the platform would have allowed six times that | Align them: `ShutdownTimeout` a few seconds *under* `terminationGracePeriodSeconds` (config); raise the grace period for genuinely slow drains (manifest) |
| **Background work ignoring its token** | `BackgroundService.ExecuteAsync` gets a cancellation token at shutdown; work that loops without observing it doesn't stop; it gets SIGKILLed mid-item | Honor the token at every await; on cancellation, checkpoint or requeue the current item and return. Shutdown-correctness of queue consumers is exactly this |
| **The endpoint-removal race** | Endpoint propagation lags SIGTERM by a beat, traffic keeps arriving for a second or two after shutdown starts, and an instantly-closed listener answers it with connection refused: 5xx blips on *every* deploy | `preStop: exec: sleep 5` in the manifest, the pod serves while the fleet's routing catches up. (This is the fix that lives in Kubernetes, not in C#) |

**Exit-code forensics**, the container's last state tells you which contract broke: exit `0` = graceful shutdown completed; `143` (128+SIGTERM) = the process died *with* the signal rather than handling it (PID 1 trap, usually); `137` (128+SIGKILL) = the deadline hit, either the grace period expired mid-drain or the OOM killer fired (`lastState.terminated.reason: OOMKilled`, which skips SIGTERM entirely and lands on the resources row above: an OOM kill is the one shutdown you get no vote in).

Two course tie-ins make this observable rather than theoretical. Stage 09's SLO gate *sees* bad shutdown behavior: a service that drops connections on rollout burns error budget on every deploy, so the gate converts sloppy draining from folklore into a red gate. And [stage 19's Reloader](../act-5/stage-19.md) means secret rotation re-rolls pods too: shutdown correctness gets exercised by routine operations, not just releases. (The stage-08 baseline deliberately doesn't set `terminationGracePeriodSeconds` or `preStop`; lifecycle tuning is per-workload, not a standard; what *is* standard is that every workload must survive being deleted.)

## The posture, restated

Every row above is either config the app should have anyway (DataProtection), an explicit mount that documents a real write path (`/tmp`), or a dev-time feature that shouldn't ship. That's the stage-08 lesson from the other side: **a hardened baseline doesn't fight well-built .NET services; it inventories the ways a service wasn't quite built for production yet.** Ship the baseline where failure is cheap, read the wounds, fix the workload, not the standard.

---

**Back to:** [08 - Dependencies & health](../act-3/stage-08.md)
