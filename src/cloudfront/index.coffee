import FS from "node:fs/promises"

import {
  list
  find
  addCustomHeader
} from "@dashkite/dolores/cloudfront"

import  { sprintf } from "sprintf-js"
import compress from "brotli/compress"
import { convert } from "@dashkite/bake"


import * as Time from "@dashkite/joy/time"

export default (genie, { namespace, edge }) ->

  genie.define "sky:cloudfront:list", ->
    distributions = list()
    for await { name, id, status } from distributions
      console.log sprintf "%32.32s %16s %12s", name, id, status

  genie.define "sky:cloudfront:find", ( domain ) ->
    distribution = await find domain
    console.log distribution._.Origins.Items[0].CustomHeaders

    addCustomHeader { domain, origin, name, value }
