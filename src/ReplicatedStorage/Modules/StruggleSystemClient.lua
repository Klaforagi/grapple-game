-- Compatibility entry point; escape progress is validated on the server.
return {Init = function() require(script.Parent.GrappleHud).Init() end}
