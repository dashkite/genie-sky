import { confidential } from "panda-confidential"
import prompts from "prompts"

Confidential = confidential()

import {
  parseSecretName
  getSecret
  hasSecret
  setSecret
  deleteSecret
} from "@dashkite/dolores/secrets"

generate = ({ type, name, bundle }) ->
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
      value
    when "bundle"
      result = {}
      for config in bundle
        result[ config.name ] = await generate config
      JSON.stringify result
    when "wildcard"
      throw new Error "Wildcard secrets define permission scope. Nothing to generate."
    else
      throw new Error "unknown secret type"


export default (genie, { secrets }) ->

  findConfig = (_name) -> 
    [ name, subName ] = parseSecretName _name
    if subName?
      config = secrets.find (secret) -> secret.name == name
      config.bundle.find (secret) -> secret.name == subName
    else
      secrets.find (secret) -> secret.name == name 

  # verify that all secrets in config exist
  genie.define "sky:secrets:check", ->
    missing = []
    for secret in secrets when secret.type != "wildcard"
      if !await hasSecret secret.name
        missing.push secret.name
    if missing.length > 0
      for name in missing
        console.warn "Secret [#{name}] does not exist"
      throw new Error "secrets:check failed"

  # ensures all secrets in config exist, generating missing secrets.
  genie.define "sky:secrets:put", ->
    missing = []
    for config in secrets when config.type != "wildcard"
      if !( await hasSecret config.name )
        missing.push config 
    
    if missing.length > 0
      for config in missing
        try
          await setSecret config.name, await generate config
          console.log "updated secret [#{config.name}]"
        catch error
          # we're okay if one of these fails
          console.error error.message

  # update a specific secret, creating the secret
  # if it doesn't exist already
  # useful for rotation
  genie.define "sky:secret:put", (name) ->
    if ( config = findConfig name )?
      await setSecret name, await generate config
      console.log "updated secret [#{name}]"
    else
      throw new Error "sky:secret:put failed, [#{name}] not configured"

  # TODO maybe remove this later?
  genie.define "sky:secret:get", (name) ->
    console.log await getSecret name

  genie.define "sky:secret:delete", (name) ->
    await deleteSecret name
    console.log "deleted secret [#{name}]" 

  # TODO temporary key rotation task to update key in WAF
  # See: https://github.com/dashkite/sky-alb/issues/1



