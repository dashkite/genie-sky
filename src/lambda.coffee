import FS from "fs/promises"

import {
  getSecretARN
} from "@dashkite/dolores/secrets"

import {
  getLambda
  publishLambda
  versionLambda
} from "@dashkite/dolores/lambda"

import { 
  createRole
} from "@dashkite/dolores/roles"

buildCloudWatchPolicy = (name) ->
  Effect: "Allow"
  Action: [
    "logs:CreateLogGroup"
    "logs:CreateLogStream"
    "logs:PutLogEvents"
  ]
  Resource: [ "arn:aws:logs:*:*:log-group:/aws/lambda/#{name}:*" ]

buildSecretsPolicy = (secrets) ->

  Effect: "Allow"
  Action: [ "secretsmanager:GetSecretValue" ]
  Resource: await do ->
    for secret in secrets
      await getSecretARN secret.name

export default (genie, { namespace, lambda, secrets }) ->

  # TODO add delete / teardown

  genie.define "update", [ "build", "zip" ], (environment) ->

    data = await FS.readFile "build/lambda.zip"

    name = "#{namespace}-#{environment}-lambda"

    # TODO possibly explore how to split out role building
    # TODO determine other policies dynamically...
    role = await createRole "#{name}-role", [
      ( buildCloudWatchPolicy name )
      ( await buildSecretsPolicy secrets )
    ]

    await publishLambda name, data, {
      lambda...
      role
    }
    
    # TODO add versioning, but we need to garbage collect...
    # await versionLambda "#{prefix}-origin-request"
