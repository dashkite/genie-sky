import * as m from "@dashkite/masonry"
import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as K from "@dashkite/katana/sync"

import {
  hasBucket
  putBucket
  deleteBucket
  emptyBucket
  getBucketLifecycle
  putBucketLifecycle
  deleteBucketLifecycle
  getObject
  putObject
} from "@dashkite/dolores/bucket"

import prompts from "prompts"

export default ( genie, options ) ->
  if options.buckets?
    { buckets } = options

    buildLifecycleRules = (bucket) ->
      switch bucket.type ? "vanilla"
        when "vanilla"
          # Default bucket. Private, no expiry, no special modes.
          null
        when "temporary-workspace"
          # Figure out a way to make this more configurable in the future.
          Rules: [
            ID: "3 Day Whiteboard"
            Expiration:
              Days: 3
            Filter:
              Prefix: ""
            Status: "Enabled"
          ]
        else
          throw new Error "unknown bucket type"

    _putBucket = (bucket) ->
      await putBucket bucket.name
      if ( rules = buildLifecycleRules bucket )?
        await putBucketLifecycle bucket.name, buildLifecycleRules bucket
      else
        await deleteBucketLifecycle bucket.name


    genie.define "sky:buckets:check", ->
      missing = []
      for bucket in buckets
        if !( await hasBucket bucket.name )
          missing.push bucket.name
      if missing.length == 0
        console.log "All buckets are available."
      else
        for name in missing
          console.warn "Bucket [#{name}] does not exist or is unavailable"
        throw new Error "buckets:check failed"

    genie.define "sky:buckets:put", ->
      for bucket in buckets
        await _putBucket bucket

    genie.define "sky:bucket:put", (name) ->
      if ( bucket = buckets.find (b) -> b.name == name )?
        await _putBucket bucket
      else
        throw new Error "configuration is not available for bucket [#{name}]"

    genie.define "sky:bucket:empty", (name) ->
      if await hasBucket name
        await emptyBucket name
      else
        throw new Error "bucket [#{name}] does not exist"

    genie.define "sky:bucket:delete", (name) ->
      if await hasBucket name
        await emptyBucket name
        await deleteBucket name
      else
        throw new Error "bucket [#{name}] does not exist"

    genie.define "sky:bucket:get", (name) ->
      { value } = await prompts
        type: "text"
        name: "value"
        message: "Key for bucket [ #{name} ]:"
      console.log await getObject name, value

    # TODO we should do a delta here, not a straight put
    genie.define "sky:bucket:publish", (name) ->

      { publish } = buckets.find ( bucket ) -> name == bucket.name

      do m.start [
        m.glob ( publish.glob ? "**/*" ), ( publish.root ? "." )
        m.read
        It.map Fn.flow [
          K.read "input"
          K.read "source"
          K.push ( source, input ) ->
            Bucket: name
            Key: source.path
            Body: input
          K.peek putObject
        ]
      ]