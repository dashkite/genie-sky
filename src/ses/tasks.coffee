import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { 
  publishTemplate
  deleteTemplate 
} from "@dashkite/dolores/ses"
import { log } from "@dashkite/dolores/logger"
import * as DRN from "@dashkite/drn-sky"

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
      root = ses?.root ? Path.join "build", "email"
      for template in ses.templates
        { html, text } = await Templates.load root, template.name
        console.log "Publishing template: #{ template.name }"
        await publishTemplate { template..., html, text }

  undeploy: ({  ses }) ->
    if ses.templates?
      for { name } in ses.templates
        console.log "Deleting template: #{ name }"
        await deleteTemplate name

export default Tasks
