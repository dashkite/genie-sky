import FS from "fs/promises"

import {
  getSecretARN
} from "@dashkite/dolores/secrets"
import {
  publishLambda
  versionLambda
} from "@dashkite/dolores/lambda"

import { 
  createRole
} from "@dashkite/dolores/roles"

buildSecretsPolicy = (secrets) ->
  Effect: "Allow"
  Action: [ "secretsmanager:GetSecretValue" ]
  Resource: do ->
    for secret in secrets
      await getSecretARN secret.name

export default (genie, options) ->

  genie.define "publish", [ "build", "zip" ], (environment) ->

    data = await FS.readFile "build/lambda.zip"

    name = "#{options.name}-#{environment}"

    { secrets } = genie.get "sky"

    role = await createRole "#{name}-role", [
      ( await buildSecretsPolicy secrets )
    ]

    await publishLambda name, data, {
      options.lambda...
      role
    }
    
    # TODO add versioning, but we need to garbage collect...
    # await versionLambda "#{prefix}-origin-request"

