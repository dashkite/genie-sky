import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { 
  publishTemplate
  deleteTemplate 
} from "@dashkite/dolores/ses"
import { log } from "@dashkite/dolores/logger"

read = ( path ) -> FS.readFile path, "utf8"

Templates =

  load: ( root, name ) ->
    [ html, text ] = await Promise.all [
      read Path.resolve root, "#{ name }.html"
      read Path.resolve root, "#{ name }.md"
    ]
    { html, text }

Tasks =

  deploy: ({ ses }) ->
    if ses.templates?
      root = ses?.root
      for template in ses.templates
        { html, text } = await Templates.load root, template.basename
        console.log "Publishing template: #{ template.name }"
        await publishTemplate { template..., html, text }

  undeploy: ({  ses }) ->
    if ses.templates?
      for { name } in ses.templates
        console.log "Deleting template: #{ name }"
        await deleteTemplate name

export default Tasks
