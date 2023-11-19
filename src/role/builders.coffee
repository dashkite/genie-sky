import {
  getSecretARN
  getWildcardARN
} from "@dashkite/dolores/secrets"

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

Builders =

  cloudwatch: ({ name, region }) ->
    region ?= "us-east-1"
    [
      Effect: "Allow"
      Action: [
        "logs:CreateLogGroup"
        "logs:CreateLogStream"
        "logs:PutLogEvents"
      ]
      Resource: [ 
        "arn:aws:logs:*:*:log-group:/aws/lambda/#{ name }:*" 
        "arn:aws:logs:*:*:log-group:/aws/lambda/#{ region }.#{ name }:*" 
      ]
    ]
  # TODO re-implement wildcard secret support
  #      maybe via DRN subtype?
  secret: ({ name }) ->
    [
      Effect: "Allow"
      Action: [ "secretsmanager:GetSecretValue" ]
      Resource: await do ->
        console.log "Authorize secret access for: #{ name }"
        await getSecretARN qname
    ]

  "s3:domain": _s3 = ({ name }) ->

    [
      Effect: "Allow"
      Action: [ "s3:*" ]
      Resource: await do ->
        resources = []
        resources.push "arn:aws:s3:::#{ name }"
        resources.push "arn:aws:s3:::#{ name }/*"
        resources
    ]

  "s3:regional:domain": _s3

  kms: ->

    # TODO allow for use of keys
    # see also: https://github.com/pandastrike/sky-mixin-kms/blob/master/src/policy.coffee#L4-L26

    [

      Effect: "Allow"
      Action: [
        "kms:GenerateRandom"
      ]
      Resource: [ "*" ]

    ]

  lambda: ({ name }) ->
    [

      Effect: "Allow"
      Action: [
        "lambda:InvokeFunction"
      ]
      Resource: [
        await getLambdaUnqualifiedARN name
      ]

    ]

  ses: ->
    [

      Effect: "Allow"
      Action: [
        "ses:SendTemplatedEmail"
      ]
      Resource: [
        "arn:aws:ses:*:*:identity/dashkite.com"
      ]

    ]

  cloudfront: ->
    [

      Effect: "Allow"
      Action: [
        "cloudfront:ListDistributions"
        "cloudfront:CreateInvalidation"
      ]
      Resource: [ "*" ]

    ]

  "step-function": do (self = false, managed = null) ->
    managed = [
        Effect: "Allow"
        Action: [
          "events:PutTargets"
          "events:PutRule"
          "events:DescribeRule"
        ]
        Resource: [
          "arn:aws:events:*:*:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"
        ]
      ,
        Effect: "Allow"
        Action:[
          "states:DescribeExecution"
          "states:StopExecution"
          "states:ListStateMachines"
        ]
        Resource: "*"
    ]

    ({ name }) ->
      policies = [
        Effect: "Allow"
        Action: [ 
          "states:startExecution" 
        ]
        Resource: [ await getStepFunctionARN name ]      
      ]

      if self == false
        policies.push managed...
        self = true

      policies

  "dynamodb:table": ({ name }) ->

    arn = getTableARN name

    [
      Effect: "Allow"
      Action: [ "dynamodb:*" ]
      Resource: [ arn, "#{ arn }/*" ]
    ]

  sqs: ({ name }) ->
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
      Resource: await SQS.getARN qname

    ]

  sns: ({ name }) ->
    [
      Effect: "Allow"
      Action: [
        "sns:CreateTopic"
        "sns:DeleteTopic"
        "sns:Publish"
        "sns:Subscribe"
      ]
      Resource: ( await getTopic name ).arn
    ]
    
# aliases
Builders.queue = Builders.sqs
Builders.topic = Builders.sns

export default Builders