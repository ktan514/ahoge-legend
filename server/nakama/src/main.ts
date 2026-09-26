const healthRpc: nkruntime.RpcFunction = function (
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  _payload: string
): string {
  if (ctx.userId) {
    logger.warn("ahoge_health rejected a user-session request.");
    throw new Error("ahoge_health is server-to-server only");
  }

  return JSON.stringify({
    service: "ahoge-legend",
    status: "ok",
    runtime: "typescript"
  });
};

let InitModule: nkruntime.InitModule = function (
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("ahoge_health", healthRpc);
  logger.info("AHOGE LEGEND TypeScript runtime loaded.");
};
