AutoIncRange = 5;

MyNodeId = 1;
NodeData = {};
table.insert(NodeData, {ip     = "127.0.0.1",      port = 8080,
                        domain = "www.retwis.com", synced = 0});
table.insert(NodeData, {ip     = "127.0.0.1",      port = 8081,
                        domain = "www.retwis.com", synced = 0});
table.insert(NodeData, {ip     = "127.0.0.1",      port = 8082,
                        domain = "www.retwis.com", synced = 0});
table.insert(NodeData, {ip     = "127.0.0.1",      port = 8083,
                        domain = "www.retwis.com", synced = 0});

BridgeData = {ip     = "127.0.0.1",      port = 9999,
              domain = "www.retwis.com", synced = 0};

PeerData = {1, 2, -1};


-- CONSTANT CONSTANT CONSTANT CONSTANT CONSTANT CONSTANT CONSTANT CONSTANT
NumNodes  = #NodeData;
NumPeers  = #PeerData;
NumToSync = #PeerData - 1; -- not self

MyGeneration = redis("get", "alchemy_generation");
if (MyGeneration == nil) then MyGeneration = 0; end
MyGeneration = MyGeneration + 1; -- This is the next generation
redis("set", "alchemy_generation", MyGeneration);
print('MyGeneration: ' .. MyGeneration);

-- WHITELISTED_FUNCTIONS WHITELISTED_FUNCTIONS WHITELISTED_FUNCTIONS
dofile "./docroot/DIST/whitelist.lua";
