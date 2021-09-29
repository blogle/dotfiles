import XMonad
import XMonad.Actions.Volume
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
  , ((0, xF86XK_AudioMute          ), toggleMute >> return ())
  , ((0, xF86XK_AudioLowerVolume   ), lowerVolume 4 >> return ())
  , ((0, xF86XK_AudioRaiseVolume   ), raiseVolume 4 >> return ())
  , ((0, xF86XK_AudioMicMute       ), spawn "amixer sset Capture toggle")
  , ((0, xF86XK_MonBrightnessUp    ), spawn "brightnessctl s 10%+")
  , ((0, xF86XK_MonBrightnessDown  ), spawn "brightnessctl s 10%-")
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
