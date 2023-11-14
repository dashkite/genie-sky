import * as Fn from "@dashkite/joy/function"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as DRN from "@dashkite/drn-sky"

resolve = generic 
  name: "resolve"
  default: Fn.identity

generic resolve, Type.isString, ( text ) ->
  if text.startsWith "drn:"
    try
      await DRN.resolve text
    catch error
      console.warn "Error resolving DRN [ #{ text } ]"
      console.warn error
      text
  else text

generic resolve, Type.isObject, ( object ) ->
  result = {}
  for key, value of object
    result[ key ] = await resolve value
  result

generic resolve, Type.isArray, ( array ) ->
  Promise.all do ->
    for value in array
      resolve value

export default resolve
export { resolve }