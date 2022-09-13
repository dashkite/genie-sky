import FS from "fs/promises"
import YAML from "js-yaml"

import {
  hasTable
  createTable
  deleteTable
} from "@dashkite/dolores/dynamodb"

export default (genie, { namespace, tables }) ->

  putTable = (table) ->
    if !( await hasTable table.name )
      configuration = YAML.load await FS.readFile ( table.path ? "#{table.name}.yaml" )
      await createTable {
        TableName: table.name
        configuration.main...
      }

  genie.define "sky:tables:check", ->
    missing = []
    for table in tables
      if !( await hasTable table.name )
        missing.push table.name
    if missing.length == 0
      console.log "All tables are available."
    else
      for name in missing
        console.warn "Table [#{name}] does not exist or is unavailable"
      throw new Error "tables:check failed"

  genie.define "sky:tables:put", ->
    for table in tables
      await putTable table

  genie.define "sky:table:put", (name) ->
    if ( table = tables.find (t) -> t.name == name )?
      await putTable table
    else
      throw new Error "configuration is not available for table [#{name}]"

  genie.define "sky:table:delete", (name) ->
    if await hasTable name
      await deleteTable name
    else
      throw new Error "table [#{name}] does not exist"