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

import { diff } from "../../diff"

import { yaml, getDomain, getDRN } from "@dashkite/drn"

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

updateConfig = ( config ) ->
  cfg = await yaml.read "genie.yaml"
  cfg.sky.s3 = config
  yaml.write "genie.yaml", cfg

Tasks =

  deploy: ( Genie, { s3 }) ->
    updated = false
    for bucket in s3
      if !bucket.domain?
        if bucket.uri?
          drn = await getDRN bucket.uri
          bucket.domains ?= {}
          if !bucket.domains[ drn ]?
            domain = await getDomain bucket.uri
            bucket.domains[ drn ] = domain
            await configureBucket { bucket..., domain, name: domain } 
            console.log "created bucket #{domain}"
            updated = true
    if updated then await updateConfig s3

    undeploy: ( Genie, { s3 }) ->
      updated = false
      for bucket in s3
        { domain } = bucket
        if bucket.uri?
          drn = await getDRN bucket.uri
          domain ?= bucket.domains?[ drn ]
        if domain?
          if await hasBucket domain
            await emptyBucket domain
            await deleteBucket domain
            console.log "deleted bucket #{domain}"
            if bucket.uri?
              drn = await getDRN bucket.uri
              if bucket.domains?[ drn ]?
                delete bucket.domains[ drn ]
                updated = true
          else
            throw new Error "bucket [#{domain}] does not exist"
      if updated then await updateConfig s3

    publish: ( Genie, { s3 }) ->

      for bucket in s3 when bucket.publish?

        { publish, domain } = bucket
        if bucket.uri?
          drn = await getDRN bucket.uri
          domain ?= bucket.domains[ drn ]

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