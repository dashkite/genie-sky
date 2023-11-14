import FS from "fs/promises"
import YAML from "js-yaml"

import {
  hasTable
  createTable
  deleteTable
} from "@dashkite/dolores/dynamodb"

import * as DRN from "@dashkite/drn-sky"

getTableDetail = ( path ) ->
  ( YAML.load await FS.readFile path, "utf-8" ).main

Tasks =

  deploy: ({ dynamodb }) ->
    updated = false
    for { name, path, pitr } in dynamodb.tables
      detail = await getTableDetail path
      if !( await hasTable name )
        await createTable {
          TableName: name
          detail...
        }, { pitr: pitr ? false }
        console.log "created table: [ #{ name } ]"

  undeploy: ({ dynamodb }) ->
    updated = false
    for { name } in dynamodb.tables
      if await hasTable name
        await deleteTable name
        console.log "deleted table: [ #{ name } ]"

export default Tasks