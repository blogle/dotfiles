import XMonad
import XMonad.Hooks.ManageDocks
import Graphics.X11.ExtraTypes.XF86
import qualified Data.Map as Map

myTerminal = "st"
myBorderWidth = 3
myWinBorderColor = "grey"
mySelBorderColor = "red"

--myManageHook = composeAll [
--    --isFullscreen --> (doF W.focusDown <+> doFullFloat),
--    --isDialog --> doCenterFloat,
--    --appName =? "desktop_window" --> doIgnore,
--    manageDocks
--]


-- | modMask lets you specify which modkey you want to use. The default
-- is mod1Mask ("left alt").  You may also consider using mod3Mask
-- ("right alt"), which does not conflict with emacs keybindings. The
-- "windows key" is usually mod4Mask.
myModifierKey = mod1Mask

keyMap conf@(XConfig {XMonad.modMask = modm}) = Map.fromList $
  [
    ((modm, xK_Return), spawn "rofi -show run")
  , ((0, xF86XK_AudioMute          ), spawn "amixer set Master toggle")
  , ((0, xF86XK_AudioLowerVolume   ), spawn "amixer set Master 2-")
  , ((0, xF86XK_AudioRaiseVolume   ), spawn "amixer set Master 2+")
  , ((0, xF86XK_AudioMicMute       ), spawn "amixer sset 'Capture',0 toggle")
  , ((0, xF86XK_MonBrightnessUp    ), spawn "xbacklight -inc 10")
  , ((0, xF86XK_MonBrightnessDown  ), spawn "xbacklight -dec 10")
  ]

main = do

  xmonad $ defaultConfig { 
    terminal           = myTerminal
  , startupHook        = docksStartupHook
  , layoutHook         = avoidStruts $ layoutHook defaultConfig
  , manageHook         = manageDocks
  , handleEventHook    = docksEventHook
  --, startupHook        = spawn "polybar example"
  --, logHook            = eventLogHook
  , keys               = keyBindings
  , modMask            = myModifierKey
  , borderWidth        = myBorderWidth
  , normalBorderColor  = myWinBorderColor
  , focusedBorderColor = mySelBorderColor }
  where keyBindings c = keyMap c `Map.union` keys defaultConfig c
  -- Map.union $ keyMap c $ keys defaultConfig c
