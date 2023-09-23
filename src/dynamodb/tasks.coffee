import FS from "fs/promises"
import YAML from "js-yaml"

import {
  hasTable
  createTable
  deleteTable
} from "@dashkite/dolores/dynamodb"

import * as DRN from "@dashkite/drn"

getTableDetail = ( path ) ->
  ( YAML.load await FS.readFile path, "utf-8" ).main

Tasks =

  deploy: ({ namespace, dynamodb, tables }) ->
    updated = false
    for table in tables
      drn = await DRN.resolve table.uri

      if !( await hasTable drn )
        await createTable {
          TableName: drn
          ( await getTableDetail table.path )...
        }, { pitr: table.pitr ? false }
        console.log "created table: #{drn}"

  undeploy: ({ namespace, dynamodb, tables }) ->
    updated = false
    for table in tables
      drn = await DRN.resolve table.uri
      if await hasTable drn
        await deleteTable drn
        console.log "deleted table: #{drn}"

export default Tasks