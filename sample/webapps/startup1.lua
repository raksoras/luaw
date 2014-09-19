return function(webapp, cmd)
    if (cmd == "start") then
        print("Starting script# 1 for webapp "..webapp.appRoot)
    else
        print("Stoping script# 1 for webapp "..webapp.appRoot)
    end
end