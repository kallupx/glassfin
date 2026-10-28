# M08a track work: regression test configuration

No existing test assertion was changed. The single change to the existing PoC
coordinator suite is its rig's explicit `configuration: .poc` argument. Those
assertions specify the locked PoC tier (unsupported video, static profile and
one remux retry); full M08a is now the production default and has a separate
profile, decision-table, track/subtitle and coordinator suite.

The existing origin, byte-limit, credential-query, redaction, userinfo rejection,
pinning and authorization regression assertions remain unchanged. Native test
assertions were not relaxed to accommodate Linux.
