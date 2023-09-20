Runner =
  make: ( loader ) ->
    do ( Tasks = undefined ) ->
      ( name, args... ) -> ( _args... ) ->
        Tasks ?= ( await loader() ).default
        task = Tasks[ name ]
        task args..., _args...

export { Runner }