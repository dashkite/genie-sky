import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"

import {
  hasBucket
  putBucket
  deleteBucket
  emptyBucket
  getBucketLifecycle
  putBucketLifecycle
  deleteBucketLifecycle
  putBucketPolicy
  deleteBucketPolicy
  putBucketWebsite
  getObject
  putObject
  deleteObject
  listObjects
} from "@dashkite/dolores/bucket"

import {
  getDistributionForDomain
} from "@dashkite/dolores/cloudfront"

import { diff } from "../diff"

import prompts from "prompts"

import Templates from "./templates"

Presets =

  get: ( bucket ) ->

    # default to private
    presets = new Set ( bucket.presets ? [ "private" ])

    if bucket.website?
      presets.delete "private"
      presets.add "website"

    # if not private or website then must be public
    if !( presets.has "private" )
      presets.add "public"
        
    presets

  private: ( bucket ) ->
    
    await deleteWebsite bucket.name

    putBucketLifecycle bucket.name,
      Rules: [
        ID: "Temporary"
        Expiration:
          Days: 3
        Filter:
          Prefix: ""
        Status: "Enabled"
      ]
    
  public: ( bucket ) ->
    await deleteBucketLifecycle bucket.name
    deleteBucketPolicy bucket.name

  cloudfront: ( bucket ) ->
    distribution = await getDistributionForDomain bucket.name
    putBucketPolicy bucket.name,
      Templates.cloudfront { bucket, distribution }

  website: ( bucket ) ->
    await deleteBucketLifecycle bucket.name
    await putBucketPolicy bucket.name,
      Templates.website { bucket }
    putBucketWebsite bucket.name, bucket.website


configureBucket = ( bucket ) ->

  await putBucket bucket.name

  await Promise.all do ->
    for preset from Presets.get bucket
      Presets[ preset ] bucket


export default ( genie, options ) ->

  if options.buckets?

    { buckets } = options

    genie.define "sky:s3:check", ->
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

    genie.define "sky:s3:buckets:put", ->
      for bucket in buckets
        await configureBucket bucket

    genie.define "sky:s3:bucket:put", (name) ->
      if ( bucket = buckets.find (b) -> b.name == name )?
        await configureBucket bucket
      else
        throw new Error "configuration is not available for bucket [#{name}]"

    genie.define "sky:s3:put", ( name ) ->
      if name?
        genie.run "sky:s3:bucket:put:#{ name }"
      else
        genie.run "sky:s3:buckets:put"

    genie.define "sky:s3:bucket:empty", (name) ->
      if await hasBucket name
        await emptyBucket name
      else
        throw new Error "bucket [#{name}] does not exist"

    genie.define "sky:s3:empty", ( name ) ->
      genie.run "sky:s3:bucket:empty:#{ name }"

    genie.define "sky:s3:bucket:delete", (name) ->
      if await hasBucket name
        await emptyBucket name
        await deleteBucket name
      else
        throw new Error "bucket [#{name}] does not exist"

    genie.define "sky:s3:delete", ( name ) ->
      genie.run "sky:s3:bucket:delete:#{ name }"

    genie.define "sky:s3:bucket:get", (name) ->
      { value } = await prompts
        type: "text"
        name: "value"
        message: "Key for bucket [ #{name} ]:"
      console.log await getObject name, value

    genie.define "sky:s3:get", ( name ) ->
      genie.run "sky:s3:bucket:get:#{ name }"

    genie.define "sky:s3:bucket:publish", (name) ->

      { publish } = buckets.find ( bucket ) -> name == bucket.name

      publish.encoding ?= "bytes"

      console.log "publishing to collection [ #{name} ]"

      diff publish,
        list: Fn.flow [
            -> listObjects name
            It.resolve It.map ({ Key }) -> getObject name, Key
            It.collect
          ]
        add: (key, content) -> 
          console.log "... add [ #{ key } ]"
          putObject name, key, content
        update: (key, content) ->
          console.log "... update [ #{ key } ]"
          putObject name, key, content
        delete: (key) ->
          console.log "... delete [ #{ key } ]"
          deleteObject name, key

    genie.define "sky:s3:publish", ( name ) ->
      genie.run "sky:s3:bucket:publish:#{ name }"