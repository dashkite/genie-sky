import * as DRN from "@dashkite/drn-sky"

import {
  getSecretARN
  getWildcardARN
} from "@dashkite/dolores/secrets"

import { 
  createRole
} from "@dashkite/dolores/roles"

import {
  getLambdaUnqualifiedARN
} from "@dashkite/dolores/lambda"

import {
  getStepFunctionARN
} from "@dashkite/dolores/step-function"

import {
  getBucketARN
} from "@dashkite/dolores/bucket"

import {
  getTableARN
} from "@dashkite/dolores/dynamodb"

import * as SQS from "@dashkite/dolores/sqs"

import {
  log
} from "@dashkite/dolores/logger"

import {
  create as getTopic
} from "@dashkite/dolores/sns"

buildCloudWatchPolicy = (name, handler) ->
  region = handler.region ? "us-east-1"

  Effect: "Allow"
  Action: [
    "logs:CreateLogGroup"
    "logs:CreateLogStream"
    "logs:PutLogEvents"
  ]
  Resource: [ 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{name}:*" 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{region}.#{name}:*" 
  ]

buildSecretsPolicy = (secrets) ->
  Effect: "Allow"
  Action: [ "secretsmanager:GetSecretValue" ]
  Resource: await do ->
    for secret in secrets
      if secret.type == "wildcard"
        log "secrets", "build-policy", 
          "authorize secret access for wildcard scope: #{ secret.name }"
        await getWildcardARN secret.name
      else
        log "secrets", "build-policy", 
          "authorize secret access for: #{ secret.name }"
        await getSecretARN secret.name

mixinPolicyBuilders =

  managedPolicies: (mixin) ->
    [
      managedPolicies:
          - "arn:aws:iam::618441030511:policy/WayboxManagerRole"
    ]

  secret: ({ qname }) ->
    [
      Effect: "Allow"
      Action: [ "secretsmanager:GetSecretValue" ]
      Resource: await do ->
        log "secrets", "build-policy", 
          "authorize secret access for: #{ qname }"
        await getSecretARN qname
    ]

  s3: ({ qname }) ->

    [
      Effect: "Allow"
      Action: [ "s3:*" ]
      Resource: await do ->
        resources = []
        resources.push "arn:aws:s3:::#{ qname }"
        resources.push "arn:aws:s3:::#{ qname }/*"
        resources
    ]


  kms: ->

    # TODO allow for use of keys
    # see also: https://github.com/pandastrike/sky-mixin-kms/blob/master/src/policy.coffee#L4-L26

    [

      Effect: "Allow"
      Action: [
        "kms:GenerateRandom"
      ]
      Resource: ["*"]

    ]

  lambda: ({ qname }) ->
    [

      Effect: "Allow"
      Action: [
        "lambda:InvokeFunction"
      ]
      Resource: [
        await getLambdaUnqualifiedARN qname
      ]

    ]

  ses: ->
    [

      Effect: "Allow"
      Action: [
        "ses:SendTemplatedEmail"
      ]
      Resource: [
        "arn:aws:ses:us-west-2:618441030511:identity/dashkite.com"
      ]

    ]

  cloudfront: ->
    [

      Effect: "Allow"
      Action: [
        "cloudfront:ListDistributions"
        "cloudfront:CreateInvalidation"
      ]
      Resource: ["*"]

    ]

  "step-function": do (self = false, managed = null) ->
    managed = [
        Effect: "Allow"
        Action:[
          "events:PutTargets"
          "events:PutRule"
          "events:DescribeRule"
        ]
        Resource: [
          "arn:aws:events:us-east-1:618441030511:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"
        ]
      ,
        Effect: "Allow"
        Action:[
          "states:DescribeExecution"
          "states:StopExecution"
          "states:ListStateMachines"
        ]
        Resource: '*'
    ]

    ({ qname }) ->
      policies = [
        Effect: "Allow"
        Action: [ 
          "states:startExecution" 
        ]
        Resource: [ await getStepFunctionARN qname ]      
      ]

      if self == false
        policies.push managed...
        self = true

      policies

  bucket: ({ qname }) ->
    [

      Effect: "Allow"
      Action: [
        "s3:GetObject"
        "s3:PutObject"
        "s3:DeleteObject"
      ]
      Resource: "#{ getBucketARN qname }/*"

    ]

  table: ({ qname }) ->
    arn = getTableARN qname

    [
      Effect: "Allow"
      Action: [ "dynamodb:*" ]
      Resource: [ arn, "#{ arn }/*" ]
    ]

  sqs: ({ qname }) ->
    [
      Effect: "Allow"
      Action: [
        "sqs:CreateQueue"
        "sqs:DeleteQueue"
        "sqs:GetQueueUrl"
        "sqs:DeleteMessage"
        "sqs:ReceiveMessage"
        "sqs:SendMessage"
      ]
      Resource: if qname?
        await SQS.getARN qname
      else
        "arn:aws:sqs:*:*:*"

    ]

  sns: ({ qname }) ->
    [
      Effect: "Allow"
      Action: [
        "sns:CreateTopic"
        "sns:DeleteTopic"
        "sns:Publish"
        "sns:Subscribe"
      ]
      Resource: ( await getTopic qname ).arn
    ]

builders = mixinPolicyBuilders
builders.queue = builders.sqs
builders.topic = builders.sns
  

buildMixinPolicy = (mixin, base) ->
  if ( builder = mixinPolicyBuilders[ mixin.type ])?
    builder mixin, base
  else
    throw new Error "Unknown mixin [ #{mixin} ] for [ #{base} ]"

Tasks =

  deploy: ( options ) ->

    {
      namespace
      lambda
      mixins
      env
      secrets
      buckets
      tables
      queues
    } = options

    mixins ?= if env?.drn?
      for mixin in env.drn
        if mixin.type?
          mixin
        else
          drn: mixin

    # TODO add delete / teardown
    # TODO add support for multiple lambdas
    
    for handler in ( lambda?.handlers ? [] )

      drn = await DRN.resolve { 
        type: "lambda"
        namespace
        name: handler.name
      }
      # TODO possibly explore how to split out role building
      # TODO allow for different policies for different handlers
      policies = [ ( buildCloudWatchPolicy drn, handler ) ]

      if secrets? && secrets.length > 0
        policies.push await buildSecretsPolicy secrets

      if mixins?
        for mixin in mixins
          configuration = if mixin.drn?
            description = DRN.decode mixin.drn
            qname = await DRN.resolve mixin.drn
            { qname, description..., mixin... }
          else mixin
          if ( builder = builders[ configuration.type ] )?
            policies.push ( await builder configuration )...

      await createRole drn, policies, options[ "managed-policies" ]


  undeploy: ( options ) ->
    { namespace, lambda } = options
    for handler in ( lambda?.handlers ? [] )
      drn = await DRN.resolve {
        type: "lambda"
        namespace
        name: handler.name 
      }
      deleteRole drn

export default Tasks

