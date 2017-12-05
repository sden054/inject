### Stop all peers
peer stop all

### Give peers some time to stop
test sleep 4

### Start peer Peer1
peer start Peer1

### Give Peer1 some time to start
test sleep 20

### Check if Peer1 was started
test waitfor 1 "Peer1.*is up"

### Show all routes
show routes all

### Check if we find the network 84.23.45.0/24
test waitfor 2 ".23.45\\.0/24\\s+193.47.73.1"

