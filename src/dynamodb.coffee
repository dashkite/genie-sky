import FS from "fs/promises"
import YAML from "js-yaml"

import {
  hasTable
  createTable
  deleteTable
} from "@dashkite/dolores/dynamodb"

import { getDRN, yaml } from "./helpers"

export default (genie, { namespace, dynamodb }) ->
  { tables } = dynamodb ? {}

  updateConfig = ( config ) ->
    cfg = await yaml.read "genie.yaml"
    cfg.sky.dynamodb.tables = config
    yaml.write "genie.yaml", cfg

  genie.define "sky:dynamodb:deploy", ->
    updated = false
    for table in tables
      drn = await getDRN table.uri
      if !( await hasTable drn )
        configuration = YAML.load await FS.readFile ( table.path ? "#{drn}.yaml" )
        await createTable {
          TableName: drn
          configuration.main...
        }, { pitr: table.pitr ? false }
        console.log "created table: #{drn}"
        table.names ?= []
        table.names.push drn
        updated = true
    if updated
      await updateConfig tables

  genie.define "sky:dynamodb:undeploy", ->
    updated = false
    for table in tables
      drn = await getDRN table.uri
      if await hasTable drn
        await deleteTable drn
        console.log "deleted table: #{drn}"
        table.names = table.names.filter ( name ) -> name != drn
        updated = true
    if updated
      await updateConfig tables