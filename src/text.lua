local text = {}

function text:TrimSpace(s)
    return s:match("^%s*(.-)%s*$")
end

return text
