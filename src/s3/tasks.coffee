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

import { log } from "@dashkite/dolores/logger"

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
      presets.add "website"

    if bucket.redirect?
      presets.delete "private"
      presets.add "redirect"

    if bucket.public?
      presets.delete "private"
      presets.add "public"

    if bucket.cloudfront?
      presets.delete "private"
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
    putBucketPolicy bucket.domain,
      Templates.website { bucket }
  
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

  publish: ({ publish, domain, drn, uri }) ->

    ( context ) ->

      publish.encoding ?= "bytes"

      drn ?= uri

      domain ?= if drn?
        await DRN.resolve drn 
      else
        throw new Error "missing bucket domain or DRN"

      putObject domain, context.source.path, context.input
  
  rm: ( bucket ) ->

    ({ domain, drn, uri }) ->

      drn ?= uri

      domain ?= if drn?
        await DRN.resolve drn 
      else
        throw new Error "missing bucket domain or DRN"

      deleteObject domain, context.source.path


Tasks =

  deploy: ({ s3 }) ->
    for bucket in s3
      { domain, drn, uri } = bucket
      bucket.domain ?= await DRN.resolve drn ? uri
      await configureBucket bucket
      log "s3", "deploy", "configured bucket #{ domain }"
    
  undeploy: ({ s3 }) ->
    for { domain, drn, uri } in s3
      domain ?= await DRN.resolve drn ? uri
      if await hasBucket domain
        await emptyBucket domain
        await deleteBucket domain
        log "s3", "undeploy", "deleted bucket #{ domain }"

  publish: ({ s3 }) ->
    
    Promise.all await do ->

      for bucket  in s3 when bucket.publish?

        { publish, domain, uri, drn } = bucket

        drn ?= uri

        domain ?= if uri?
          await DRN.resolve bucket.uri
        else
          throw new Error "missing bucket domain or DRN"
        
        log "s3", "publish", "publishing to bucket [ #{domain} ]"
            
        publish.encoding ?= "bytes"

        Diff.diff
          source: Diff.FS.glob publish
          target: Diff.S3.glob { 
            domain
            glob: bucket.glob ? "**/*"
          }
          patch: Fn.pipe [
            Fn.tee ({ action, key }) ->
              log "s3", "publish", "... #{ action } [ #{ key } ]"
              undefined # avoid returning a promise
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