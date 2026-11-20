local name, ns = ...
ns.name, ns.version = name, "0.5.1"
ns.Data, ns.Engine, ns.UI = {}, {}, {}
ns.Limits = { messageBytes = 4096, tokens = 256, cacheEntries = 128, cacheBytes = 131072 }
-- No global namespace export and no dependency on another addon's internals.
