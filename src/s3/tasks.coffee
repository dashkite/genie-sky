import FS from "node:fs/promises"
import Path from "node:path"
import * as Fn from "@dashkite/joy/function"
import M from "@dashkite/masonry"
import W from "@dashkite/masonry-watch"
import { File } from "@dashkite/masonry-module"

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
  putObject
  deleteObject
  putCORSConfig
  deletePublicAccessBlock  
} from "@dashkite/dolores/bucket"

import {
  getDistributionForDomain
} from "@dashkite/dolores/cloudfront"

import * as TK from "terminal-kit"

log = ( text ) ->
  TK.terminal.green "genie-sky/s3: #{ text }\n"

import * as Diff from "@dashkite/diff"

import * as DRN from "@dashkite/drn-sky"

import prompts from "prompts"

import Templates from "./templates"

Presets =

  get: ( bucket ) ->

    # default to private
    presets = new Set ( bucket.presets ? [ "private" ])

    if bucket.website?
      presets.delete "private"
      presets.add "public"
      presets.add "website"

    if bucket.redirect?
      presets.delete "private"
      presets.add "public"
      presets.add "redirect"

    if bucket.public?
      presets.delete "private"
      presets.add "public"

    if bucket.cloudfront?
      presets.delete "private"
      presets.add "public"
      presets.add "cloudfront"

    if bucket.cors?
      presets.add "cors"        

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
    await deletePublicAccessBlock bucket.domain
  
  cloudfront: ( bucket ) ->
    await deleteBucketLifecycle bucket.domain
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

  cors: ( bucket ) ->
    params = 
      Bucket: bucket.domain
      CORSConfiguration:
        CORSRules: [
          AllowedHeaders: [ "*" ]
          AllowedOrigins: [ "*" ]
          AllowedMethods: [ "GET", "PUT", "POST", "DELETE" ]
          MaxAgeSeconds: 7200
        ]
    putCORSConfig params

configureBucket = ( bucket ) ->
  await putBucket bucket.domain
  await Promise.all do ->
    for preset from Presets.get bucket
      Presets[ preset ] bucket

Item =

  publish: ({ publish, domain }) ->
    Fn.tee ( context ) ->
      publish.encoding ?= "bytes"
      log "publishing #{ context.source.path }"
      putObject domain, context.source.path, context.input
  
  rm: ({ domain }) ->
    Fn.tee ( context ) ->
      log "delete #{ context.source.path }"
      deleteObject domain, context.source.path


Tasks =

  deploy: ({ s3 }) ->
    for bucket in s3
      await configureBucket bucket
      console.log "Configured bucket #{ bucket.domain }"
    
  undeploy: ({ s3 }) ->
    for { domain } in s3
      if await hasBucket domain
        await emptyBucket domain
        await deleteBucket domain
        console.log "Deleted bucket #{ domain }"

  publish: ({ s3 }) ->
    
    Promise.all await do ->

      for bucket in s3 when bucket.publish?

        { publish, domain } = bucket

        console.log "Publishing to bucket [ #{domain} ]"
            
        publish.encoding ?= "bytes"

        Diff.diff
          source: Diff.FS.glob publish
          target: Diff.S3.glob { 
            domain
            glob: bucket.glob ? "**/*"
          }
          patch: Fn.pipe [
            Fn.tee ({ action, key }) ->
              console.log "... #{ action } [ #{ key } ]"
            Diff.S3.patch { domain }
          ]

  watch: ({ s3 }) ->

    watch = ( bucket ) ->
      do M.start [
        W.glob bucket.publish
        W.match type: "file", name: [ "add", "change" ], [
          M.read
          File.hash
          File.changed Fn.flow [
            File.stamp
            Item.publish bucket
            W.notify
          ]
        ]
        W.match type: "file", name: "rm", [
          File.evict
          Item.rm bucket
        ]
      ]

    Promise.all do ->
      for bucket in s3 when bucket.publish?
        watch bucket

export default Tasks