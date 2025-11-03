# Proxy System Data Structures
# Data structures for HTTP proxy communication protocol
import json

type
  ProxyRole* = enum
    GATEWAY, PIVOT, CUMULUS_AGENT

  CommunicationNode* = object
    nodeType*: string           # "node" or "null" 
    agentId*: string           # Agent ID from current system
    ip*: string                # IP:port of the node
    cumulus*: seq[CommunicationNode]  # Nested nodes
    encryptedMessage*: string  # Only for nodeType "null"

  CommunicationArray* = object
    communicationArray*: seq[CommunicationNode]

# Conversión JSON helpers
proc `%`*(node: CommunicationNode): JsonNode =
  result = newJObject()
  result["nodeType"] = %node.nodeType
  result["agentId"] = %node.agentId
  result["ip"] = %node.ip
  result["cumulus"] = %node.cumulus
  if node.encryptedMessage != "":
    result["encryptedMessage"] = %node.encryptedMessage

proc `%`*(arr: CommunicationArray): JsonNode =
  result = newJObject()
  result["communication_array"] = %arr.communicationArray

proc toCommunicationNode*(jsonNode: JsonNode): CommunicationNode =
  result.nodeType = jsonNode["nodeType"].getStr()
  result.agentId = jsonNode["agentId"].getStr()
  result.ip = jsonNode["ip"].getStr()
  
  if jsonNode.hasKey("encryptedMessage"):
    result.encryptedMessage = jsonNode["encryptedMessage"].getStr()
  
  if jsonNode.hasKey("cumulus"):
    for child in jsonNode["cumulus"]:
      result.cumulus.add(toCommunicationNode(child))

proc toCommunicationArray*(jsonNode: JsonNode): CommunicationArray =
  for node in jsonNode["communication_array"]:
    result.communicationArray.add(toCommunicationNode(node))
