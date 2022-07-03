guard = (f) ->
  (args...) ->
    if f.length > 0
      for i in [ 0..( f.length - 1 ) ]
        if !args[i]?
          throw new Error "sky:presets: this task requires all arguments to be
            specified."
    
    f args...

nameLambda = ({ namespace, environment, name }) ->
  if !namespace? || !environment? || !name?
    throw new Error "unable to form lambda function name with parameters 
      #{namespace} #{environment} #{name}"  
  
  "#{namespace}-#{environment}-#{name}"

nameRole = ({ namespace, environment, name }) ->
  if !namespace? || !environment? || !name?
    throw new Error "unable to form role name with parameters 
      #{namespace} #{environment} #{name}"  
  
  "#{namespace}-#{environment}-#{name}-role"
  

export { 
  guard
  nameLambda
  nameRole
}