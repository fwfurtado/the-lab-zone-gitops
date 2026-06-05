CREATE CONSTRAINT document_id IF NOT EXISTS
FOR (d:Document) REQUIRE d.id IS UNIQUE;

CREATE CONSTRAINT chunk_id IF NOT EXISTS
FOR (c:Chunk) REQUIRE c.chunkId IS UNIQUE;

CREATE CONSTRAINT repository_id IF NOT EXISTS
FOR (r:Repository) REQUIRE r.id IS UNIQUE;

CREATE INDEX component_name IF NOT EXISTS
FOR (n:Component) ON (n.name);

CREATE INDEX document_uri IF NOT EXISTS
FOR (d:Document) ON (d.uri);
