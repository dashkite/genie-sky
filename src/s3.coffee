import {
  hasBucket
  putBucket
  deleteBucket
  emptyBucket
  getBucketLifecycle
  putBucketLifecycle
  deleteBucketLifecycle
} from "@dashkite/dolores/bucket"

export default ( genie, options ) ->
  if options.buckets?
    { buckets } = options

    buildLifecycleRules = (bucket) ->
      switch bucket.type
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