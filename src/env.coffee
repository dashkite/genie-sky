# maybe we make this a separate task?
injectEnvironment = ( context ) ->
  if context.env?
    $ = cheerio.load context.input
    $ "head"
      .append """
        <script>
          window.process = { env: #{JSON.stringify context.build.env} }
        </script>
      """
    $.html()
  else context.input
