import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { publishSES } from "@dashkite/dolores/ses"
import { Name } from "@dashkite/name"
import { getDRN } from "./helpers"

publishTemplates = ({ namespace, ses }) ->
  for template in ses?.templates ? []
    name = await getDRN Name.getURI { type: "ses", namespace, name: template.name }
    html = await FS.readFile Path.resolve "build", "node", "email", "#{template.name}.html"
    text = await FS.readFile Path.resolve "build", "email", "#{template.name}.md"
    console.log "Publishing template: #{name}"
    await publishSES {template..., name, html, text}


export default (genie, { namespace, ses }) ->
  
  genie.define "markdown", m.start [
      m.glob "email/**/*.md", "."
      m.read
      m.copy "build"
    ]
  
  genie.after "build", "markdown"
  
  genie.define "sky:ses:publish",
    [
      "build"
    ],
    ->
      publishTemplates {
        namespace
        ses
      }