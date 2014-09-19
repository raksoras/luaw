return function(webapp, cmd)
    if (cmd == "start") then
        print("Starting script# 2 for webapp "..webapp.appRoot)
    else
        print("Stoping script# 2 for webapp "..webapp.appRoot)
    end
end