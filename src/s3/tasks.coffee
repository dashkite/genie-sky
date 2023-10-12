import FS from "node:fs/promises"
import Path from "node:path"
import * as Fn from "@dashkite/joy/function"

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


Tasks =

  deploy: ({ s3 }) ->
    updated = false
    for bucket in s3
      if !bucket.domain?
        if bucket.uri?
          drn = await DRN.resolve bucket.uri
          bucket.domains ?= {}
          if !bucket.domains[ drn ]?
            domain = await DRN.resolve bucket.uri
            bucket.domains[ drn ] = domain
            await configureBucket { bucket..., domain, name: domain } 
            log "s3", "deploy", "created bucket #{domain}"
    
  undeploy: ({ s3 }) ->
    updated = false
    for bucket in s3
      { domain } = bucket
      if bucket.uri?
        drn = await DRN.resolve bucket.uri
        domain ?= bucket.domains?[ drn ]
      if domain?
        if await hasBucket domain
          await emptyBucket domain
          await deleteBucket domain
          log "s3", "undeploy", "deleted bucket #{domain}"
          if bucket.uri?
            drn = await DRN.resolve bucket.uri
            if bucket.domains?[ drn ]?
              delete bucket.domains[ drn ]
              updated = true
        else
          throw new Error "bucket [ #{ domain } ] does not exist"

  publish: ({ s3 }) ->
    
    Promise.all await do ->

      for bucket in s3 when bucket.publish?

        { publish, domain } = bucket

        publish.encoding ?= "bytes"

        domain ?= if bucket.uri?
          await DRN.resolve bucket.uri
        else
          throw new Error "missing bucket domain or DRN"
        
        log "s3", "publish", "publishing to bucket [ #{domain} ]"
            
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

export default Tasks