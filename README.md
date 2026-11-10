# ui-object-new
## recreation of the "kimikahax for Counter-Strike: Global Offensive";
+ open Sans PX (pixel font) for text and a matching pixel bold (embedded) for values/titles,
  both at TextSize 13 (falls back to Arial when file functions are missing)
+ flat charcoal panels with 1px dark outline + 1px inner highlight, soft vertical shading
+ lavender accent (#6869a9) with glowing accent lines on active tabs / section headers
+ bold outlined slider values that ride the end of the fill

## API documentation;    
```lua
-- window;
Library:Window({Name, SubTitle, Size, Icon, MenuKeybind})

-- create page
Window:Page({Name, Columns})

-- create section;
Page:Section({Name, Side, Header})  

-- create multi section -> { SectionA, SectionB } (also keyed by name);
Page:MultiSection({Sections = {"A", "B"}, Side})

-- create toggle;
Section:Toggle({Name, Flag, Default, Risky, Tooltip, Callback})

-- create colorpicker (parent:toggle);
-- colorpicker Alpha is TRANSPARENCY (0 = opaque, 1 = invisible), matching Roblox.
-- hex strings are #RRGGBBAA where AA is that transparency (as in the original menu).
Toggle:Colorpicker({...})

-- create keybind (parent:toggle);
Toggle:Keybind({...})

-- create button (parent:section);
Section:Button({Name, Callback, Confirm}):Add(Name, Callback, Confirm)
```
