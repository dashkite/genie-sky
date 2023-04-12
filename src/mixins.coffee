import Path from "node:path"
import { Name } from "@dashkite/name"
import { getDRN, getDomain, yaml } from "./helpers"

Mixins =
  
  s3: ( uri ) ->
    getDomain uri

  graphene: (uri, genie) ->
    { namespace, name, repo } = Name.parse uri
    configuration = if repo?
      cfg = await yaml.read ( Path.join "..", repo, "genie.yaml" )
      cfg.sky.graphene.find ( description ) ->
        components = Name.parse description.uri
        components.namespace == namespace &&
          components.name == name
    else
      genie.get "sky"
        .graphene
        .find ( description ) ->
          components = Name.parse description.uri
          components.namespace == namespace &&
            components.name == name
    drn = await getDRN uri
    configuration.addresses?[ drn ]

  ses: ( uri ) ->
    getDRN uri

  lambda: ( uri ) ->
    getDRN uri

  domain: ( uri ) ->
    getDomain uri

  secret: ( uri ) ->
    getDRN uri

  origin: ( uri ) ->
    "https://#{ await getDomain uri }"

  apply: ( descriptions, genie ) ->
    configurations = {}
    if descriptions?
      for { uri } in descriptions when uri?
          { type } = Name.parse uri
          if (handler = Mixins[ type ])?
            configurations[ uri ] = await handler uri, genie
    configurations

export { Mixins }