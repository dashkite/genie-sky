import { confidential } from "panda-confidential"
import prompts from "prompts"

Confidential = confidential()

import {
  getSecret
  hasSecret
  setSecret
} from "@dashkite/dolores/secrets"

generate = (type, name) ->
  switch type
    when "random-16"
      Confidential.convert from: "bytes", to: "base36",
        await Confidential.randomBytes 16
    when "encryption-keypair"
      (await Confidential.EncryptionKeyPair.create())
        .to "base64"
    when "signature-keypair"
      (await Confidential.SignatureKeyPair.create())
        .to "base64"
    when "environment"
      if ( value = process.env[ name ] )?
        value
      else
        throw new Error "Secret [#{name}] environment variable not set"
    when "prompt"
      { value } = await prompts
        type: "password"
        name: "value"
        message: "Enter secret [ #{name} ]:"
      valuegen

export default (genie, { secrets }) ->
  
  # verify that all secrets in config exist
  genie.define "secrets:check", ->
    missing = []
    for secret in secrets
      if !await hasSecret secret.name
        missing.push secret.name
    if missing.length > 0
      for name in missing
        console.warn "Secret [#{name}] does not exist"
      throw new Error "secrets:check failed"

  # ensures all secrets in config exist,
  # generating values if they don't
  genie.define "secrets:put", ->
    missing = []
    for secret in secrets
      if !await hasSecret secret.name
        missing.push secret
    if missing.length > 0
      for secret in missing
        try
          await setSecret secret.name,
            await generate secret.type, secret.name
        catch error
          # we're okay if one of these fails
          console.error error.message

  # update a specific secret, creating the secret
  # if it doesn't exist already
  # useful for rotation
  genie.define "secret:put", (name) ->
    for secret in secrets when secret.name == name
      await setSecret secret.name,
        await generate secret.type, secret.name
      return
    throw new Error "secret:put failed, [#{name}] not configured"

  # TODO maybe remove this later?
  genie.define "secret:get", (name) ->
    console.log await getSecret name

  # TODO temporary key rotation task to update key in WAF
  # See: https://github.com/dashkite/sky-alb/issues/1



