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

  deploy: ({ namespace, ses }) ->
    templates = ses?.templates ? []
    root = ses?.root ? Path.join "build", "email"
    for template in templates
      name = await DRN.resolve {
        type: "ses"
        namespace
        name: template.name 
      }
      { html, text } = await Templates.load root, template.name
      log "ses", "deploy", "Publishing template: #{ name }"
      await publishTemplate { template..., name, html, text }

  undeploy: ({ namespace, ses }) ->
    for template in ses?.templates ? []
      name = await DRN.resolve {
        type: "ses"
        namespace
        name: template.name 
      }
      log "ses", "undeploy", "Deleting template: #{ name }"
      await deleteTemplate name

export default Tasks
