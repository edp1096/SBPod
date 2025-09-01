local text = {}

-- Trim whitespace from both ends of string
function text:TrimSpace(s)
    -- if not s then return nil end
    return s:match("^%s*(.-)%s*$")
end

-- Split string by separator
function text:Split(str, sep)
    if not str then return {} end
    if not sep then sep = "%s" end -- Default to whitespace

    local result = {}
    local pattern

    -- Special handling for whitespace separators
    if sep == " " or sep == "%s" then
        -- Handle multiple consecutive spaces as single separator
        pattern = "([^%s]+)"
        for part in string.gmatch(str, pattern) do
            table.insert(result, part)
        end
    else
        -- Handle other separators (escape special pattern characters)
        local escaped_sep = sep:gsub("([%.%+%-%*%?%[%]%(%)%^%$%%])", "%%%1")
        pattern = "([^" .. escaped_sep .. "]+)"
        for part in string.gmatch(str, pattern) do
            table.insert(result, part)
        end
    end

    return result
end

-- -- Alternative: Split with exact whitespace handling
-- function text:SplitExact(str, sep)
--     if not str then return {} end
--     if not sep then sep = " " end -- Single space default

--     local result = {}
--     local start = 1
--     local sep_len = #sep

--     while true do
--         local pos = string.find(str, sep, start, true) -- Plain text search
--         if pos then
--             local part = string.sub(str, start, pos - 1)
--             table.insert(result, part) -- Include empty strings
--             start = pos + sep_len
--         else
--             local part = string.sub(str, start)
--             table.insert(result, part)
--             break
--         end
--     end

--     return result
-- end

-- Get first part before separator (your original use case)
function text:GetFirstPart(str, sep)
    if not str then return nil end
    if not sep then sep = "_" end

    local parts = self:Split(str, sep)
    return parts[1]
end

-- Additional utility: Join array with separator
function text:Join(array, sep)
    if not array then return "" end
    if not sep then sep = " " end
    return table.concat(array, sep)
end

-- -- Test the module
-- local test_string = "Gigas_Wasteland_More_Parts"
-- print("Original:", test_string)
-- print("Split by underscore:", table.concat(text:Split(test_string, "_"), ", "))
-- print("First part:", text:GetFirstPart(test_string, "_"))

-- -- Test with spaces
-- local space_test = "Hello   World    Lua   Code"
-- print("\nSpace tests:")
-- print("Original:", "'" .. space_test .. "'")
-- print("Split by space (auto-collapse):", table.concat(text:Split(space_test, " "), ", "))
-- print("Split exact spaces:", table.concat(text:SplitExact(space_test, " "), ", "))

-- -- More space examples
-- local simple_space = "Apple Banana Cherry"
-- print("\nSimple space example:")
-- print("Original:", simple_space)
-- print("Split result:", table.concat(text:Split(simple_space, " "), ", "))
-- print("First part:", text:GetFirstPart(simple_space, " "))

-- print("Trimmed:", "'" .. text:TrimSpace("  spaced text  ") .. "'")

return text
