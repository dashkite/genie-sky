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
  deleteBucketWebsite
  putBucketRedirect
  getObject
  putObject
  deleteObject
  listObjects
} from "@dashkite/dolores/bucket"

import {
  getDistributionForDomain
} from "@dashkite/dolores/cloudfront"

import { diff } from "../diff"

import { yaml, getDomain } from "../helpers"

import prompts from "prompts"

import Templates from "./templates"

Presets =

  get: ( bucket ) ->

    # default to private
    presets = new Set ( bucket.presets ? [ "private" ])

    if bucket.website?
      presets.delete "private"
      presets.add "website"

    if bucket.redirect?
      presets.delete "private"
      presets.add "redirect"

    # if not private or website then must be public
    if !( presets.has "private" )
      presets.add "public"
        
    presets

  private: ( bucket ) ->
    
    await deleteBucketWebsite bucket.domain

    putBucketLifecycle bucket.domain,
      Rules: [
        ID: "Temporary"
        Expiration:
          Days: 3
        Filter:
          Prefix: ""
        Status: "Enabled"
      ]
    
  public: ( bucket ) ->
    await deleteBucketLifecycle bucket.domain
    deleteBucketPolicy bucket.domain

  cloudfront: ( bucket ) ->
    distribution = await getDistributionForDomain bucket.domain
    putBucketPolicy bucket.domain,
      Templates.cloudfront { bucket, distribution }

  website: ( bucket ) ->
    await deleteBucketLifecycle bucket.domain
    await putBucketPolicy bucket.domain,
      Templates.website { bucket }
    putBucketWebsite bucket.domain, bucket.website

  redirect: ( bucket ) ->
    await deleteBucketLifecycle bucket.domain
    putBucketRedirect bucket.domain, bucket.redirect

configureBucket = ( bucket ) ->

  await putBucket bucket.domain

  await Promise.all do ->
    for preset from Presets.get bucket
      Presets[ preset ] bucket

updateConfig = ( config ) ->
  cfg = await yaml.read "genie.yaml"
  cfg.sky.s3 = config
  yaml.write "genie.yaml", cfg

export default ( genie, { s3 } ) ->

    genie.define "sky:s3:deploy", ->
      updated = false
      for bucket in s3
        if !bucket.domain?
          bucket.domain = await getDomain bucket.uri
          await configureBucket bucket
          console.log "created bucket #{bucket.domain}"
          updated = true
      if updated then await updateConfig s3

    genie.define "sky:s3:undeploy", ->
      updated = false
      for bucket in s3
        if bucket.domain?
          if await hasBucket bucket.domain
            await emptyBucket bucket.domain
            await deleteBucket bucket.domain
            console.log "deleted bucket #{bucket.domain}"
            delete bucket.domain
            updated = true
          else
            throw new Error "bucket [#{bucket.domain}] does not exist"
      if updated then await updateConfig s3

    genie.define "sky:s3:publish", [ "sky:s3:deploy" ], ->

      for bucket in s3 when bucket.publish?

        { publish, domain } = bucket

        publish.encoding ?= "bytes"

        console.log "publishing to bucket [ #{domain} ]"

        diff publish,
          list: Fn.flow [
              -> listObjects domain
              It.resolve It.map ({ Key }) -> getObject domain, Key
              It.collect
            ]
          add: (key, content) -> 
            console.log "... add [ #{ key } ]"
            putObject domain, key, content
          update: (key, content) ->
            console.log "... update [ #{ key } ]"
            putObject domain, key, content
          delete: (key) ->
            console.log "... delete [ #{ key } ]"
            deleteObject domain, key