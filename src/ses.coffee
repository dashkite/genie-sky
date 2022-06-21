import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { guard } from "./helpers"
import { publishSES } from "@dashkite/dolores/ses"

publishTemplates = ({ namespace, environment, ses }) ->
  for template in ses?.templates ? []
    name = "#{namespace}-#{environment}-#{template.name}"
    html = await FS.readFile Path.resolve "build", "node", "email", "#{template.name}.html"
    text = await FS.readFile Path.resolve "build", "email", "#{template.name}.md"
    console.log name
    await publishSES {template..., name, html, text}


export default (genie, { namespace, ses }) ->
  
  genie.define "markdown", m.start [
      m.glob "email/**/*.md", "."
      m.read
      m.copy "build"
    ]
  
  genie.after "build", "markdown"
  
  genie.define "sky:ses:templates:publish",
    [
      "build"
    ],
    guard (environment) ->
      publishTemplates {
        namespace
        environment
        ses
      }