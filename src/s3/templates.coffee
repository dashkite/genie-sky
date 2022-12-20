import { expand } from "@dashkite/polaris"
import cloudfront from "./cloudfront"
import website from "./website"

Templates =
  cloudfront: ( context ) -> expand cloudfront, context
  website: ( context ) -> expand website, context

export default Templates