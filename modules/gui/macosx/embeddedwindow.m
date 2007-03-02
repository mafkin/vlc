/*****************************************************************************
 * embeddedwindow.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2005-2006 the VideoLAN team
 * $Id$
 *
 * Authors: Benjamin Pracht <bigben at videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

/* DisableScreenUpdates, SetSystemUIMode, ... */
#import <QuickTime/QuickTime.h>

#import "intf.h"
#import "controls.h"
#import "vout.h"
#import "embeddedwindow.h"
#import "fspanel.h"

/*****************************************************************************
 * VLCEmbeddedWindow Implementation
 *****************************************************************************/

@implementation VLCEmbeddedWindow

- (void)awakeFromNib
{
    [self setDelegate: self];

    [o_btn_backward setToolTip: _NS("Rewind")];
    [o_btn_forward setToolTip: _NS("Fast Forward")];
    [o_btn_fullscreen setToolTip: _NS("Fullscreen")];
    [o_btn_play setToolTip: _NS("Play")];
    [o_slider setToolTip: _NS("Position")];

    o_img_play = [NSImage imageNamed: @"play_embedded"];
    o_img_play_pressed = [NSImage imageNamed: @"play_embedded_blue"];
    o_img_pause = [NSImage imageNamed: @"pause_embedded"];
    o_img_pause_pressed = [NSImage imageNamed: @"pause_embedded_blue"];

    o_saved_frame = NSMakeRect( 0.0f, 0.0f, 0.0f, 0.0f );

    /* Useful to save o_view frame in fullscreen mode */
    o_temp_view = [[NSView alloc] init];
    [o_temp_view setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];

    o_fullscreen_window = nil;
    o_fullscreen_anim1 = o_fullscreen_anim2 = nil;

    /* Not fullscreen when we wake up */
    [o_btn_fullscreen setState: NO];
}

- (void)setTime:(NSString *)o_arg_time position:(float)f_position
{
    [o_time setStringValue: o_arg_time];
    [o_slider setFloatValue: f_position];
}

- (void)playStatusUpdated:(int)i_status
{
    if( i_status == PLAYING_S )
    {
        [o_btn_play setImage: o_img_pause];
        [o_btn_play setAlternateImage: o_img_pause_pressed];
        [o_btn_play setToolTip: _NS("Pause")];
    }
    else
    {
        [o_btn_play setImage: o_img_play];
        [o_btn_play setAlternateImage: o_img_play_pressed];
        [o_btn_play setToolTip: _NS("Play")];
    }
}

- (void)setSeekable:(BOOL)b_seekable
{
    [o_btn_forward setEnabled: b_seekable];
    [o_btn_backward setEnabled: b_seekable];
    [o_slider setEnabled: b_seekable];
}

- (void)zoom:(id)sender
{
    if( ![self isZoomed] )
    {
        NSRect zoomRect = [[self screen] frame];
        o_saved_frame = [self frame];
        /* we don't have to take care of the eventual menu bar and dock
          as zoomRect will be cropped automatically by setFrame:display:
          to the right rectangle */
        [self setFrame: zoomRect display: YES animate: YES];
    }
    else
    {
        /* unzoom to the saved_frame if the o_saved_frame coords look sound
           (just in case) */
        if( o_saved_frame.size.width > 0 && o_saved_frame.size.height > 0 )
            [self setFrame: o_saved_frame display: YES animate: YES];
    }
}

- (BOOL)windowShouldClose:(id)sender
{
    playlist_t * p_playlist = pl_Yield( VLCIntf );

    playlist_Stop( p_playlist );
    vlc_object_release( p_playlist );
    return YES;
}

/*****************************************************************************
 * Fullscreen support
 */
- (void)enterFullscreen
{
    NSMutableDictionary *dict1, *dict2;
    NSScreen *screen;
    NSRect screen_rect;
    NSRect rect;
    vout_thread_t *p_vout = vlc_object_find( VLCIntf, VLC_OBJECT_VOUT, FIND_ANYWHERE );
    BOOL blackout_other_displays = var_GetBool( p_vout, "macosx-black" );

    screen = [NSScreen screenWithDisplayID:(CGDirectDisplayID)var_GetInteger( p_vout, "video-device" )];

    vlc_object_release( p_vout );

    if (!screen)
        screen = [self screen];

    screen_rect = [screen frame];

    [o_btn_fullscreen setState: YES];

    [NSCursor setHiddenUntilMouseMoves: YES];
    
    if (blackout_other_displays)
        [screen blackoutOtherScreens]; /* We should do something like [screen blackoutOtherScreens]; */

    /* Only create the o_fullscreen_window if we are not in the middle of the zooming animation */
    if (!o_fullscreen_window)
    {
        /* We can't change the styleMask of an already created NSWindow, so we create an other window, and do eye catching stuff */

        rect = [[o_view superview] convertRect: [o_view frame] toView: nil]; /* Convert to Window base coord */
        rect.origin.x += [self frame].origin.x;
        rect.origin.y += [self frame].origin.y;
        o_fullscreen_window = [[VLCWindow alloc] initWithContentRect:rect styleMask: NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
        [o_fullscreen_window setBackgroundColor: [NSColor blackColor]];
        [o_fullscreen_window setCanBecomeKeyWindow: YES];

        if (![self isVisible] || [self alphaValue] == 0.0 || MACOS_VERSION < 10.4f)
        {
            /* We don't animate if we are not visible or if we are running on
             * Mac OS X <10.4 which doesn't support NSAnimation, instead we
             * simply fade the display */
            CGDisplayFadeReservationToken token;
            
            [o_fullscreen_window setFrame:screen_rect display:NO];
            
            CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
            CGDisplayFade( token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES );
            
            if (screen == [NSScreen mainScreen])
                SetSystemUIMode( kUIModeAllHidden, kUIOptionAutoShowMenuBar);
            
            [[self contentView] replaceSubview:o_view with:o_temp_view];
            [o_temp_view setFrame:[o_view frame]];
            [o_fullscreen_window setContentView:o_view];
            [o_fullscreen_window makeKeyAndOrderFront:self];
            [self orderOut: self];

            CGDisplayFade( token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO );
            CGReleaseDisplayFadeReservation( token);
            [self hasBecomeFullscreen];
            return;
        }
        
        /* Make sure we don't see the o_view disappearing of the screen during this operation */
        DisableScreenUpdates();
        [[self contentView] replaceSubview:o_view with:o_temp_view];
        [o_temp_view setFrame:[o_view frame]];
        [o_fullscreen_window setContentView:o_view];
        [o_fullscreen_window makeKeyAndOrderFront:self];
        EnableScreenUpdates();
    }

    if (MACOS_VERSION < 10.4f)
    {
        /* We were already fullscreen nothing to do when NSAnimation
         * is not supported */
        return;
    }

    if (o_fullscreen_anim1)
    {
        [o_fullscreen_anim1 stopAnimation];
        [o_fullscreen_anim1 release];
    }
    if (o_fullscreen_anim2)
    {
        [o_fullscreen_anim2 stopAnimation];
        [o_fullscreen_anim2 release];
    }
 
    if (screen == [NSScreen mainScreen])
        SetSystemUIMode( kUIModeAllHidden, kUIOptionAutoShowMenuBar);

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:2];
    dict2 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:self forKey:NSViewAnimationTargetKey];
    [dict1 setObject:NSViewAnimationFadeOutEffect forKey:NSViewAnimationEffectKey];

    [dict2 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict2 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict2 setObject:[NSValue valueWithRect:screen_rect] forKey:NSViewAnimationEndFrameKey];

    /* Strategy with NSAnimation allocation:
        - Keep at most 2 animation at a time
        - leaveFullscreen/enterFullscreen are the only responsible for releasing and alloc-ing
    */
    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict1, nil]];
    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict2, nil]];

    [dict1 release];
    [dict2 release];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.3];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.2];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];

    [o_fullscreen_anim1 startAnimation];
}

- (void)hasBecomeFullscreen
{
    [o_fullscreen_window makeFirstResponder: [[[VLCMain sharedInstance] getControls] getVoutView]];

    [o_fullscreen_window makeKeyWindow];
    [o_fullscreen_window setAcceptsMouseMovedEvents: TRUE];

    /* tell the fspanel to move itself to front next time it's triggered */
    [[[[VLCMain sharedInstance] getControls] getFSPanel] setVoutWasUpdated: (int)[[o_fullscreen_window screen] displayID]];
    
    [[[[VLCMain sharedInstance] getControls] getFSPanel] setActive: nil];
}

- (void)leaveFullscreen
{
    NSMutableDictionary *dict1, *dict2;
    NSRect frame;
    
    [o_btn_fullscreen setState: NO];

    /* We always try to do so */
    [NSScreen unblackoutScreens];

    /* Don't do anything if o_fullscreen_window is already closed */
    if (!o_fullscreen_window)
        return;

    if (MACOS_VERSION < 10.4f)
    {
        /* We don't animate if we are not visible or if we are running on
        * Mac OS X <10.4 which doesn't support NSAnimation, instead we
        * simply fade the display */
        CGDisplayFadeReservationToken token;

        CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
        CGDisplayFade( token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES );

        [[[[VLCMain sharedInstance] getControls] getFSPanel] setNonActive: nil];
        SetSystemUIMode( kUIModeNormal, kUIOptionAutoShowMenuBar);

        [self makeKeyAndOrderFront:self];
        [self hasEndedFullscreen];

        CGDisplayFade( token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO );
        CGReleaseDisplayFadeReservation( token);
        return;
    }

    [[[[VLCMain sharedInstance] getControls] getFSPanel] setNonActive: nil];
    SetSystemUIMode( kUIModeNormal, kUIOptionAutoShowMenuBar);

    if (o_fullscreen_anim1)
    {
        [o_fullscreen_anim1 stopAnimation];
        [o_fullscreen_anim1 release];
    }
    if (o_fullscreen_anim2)
    {
        [o_fullscreen_anim2 stopAnimation];
        [o_fullscreen_anim2 release];
    }

    frame = [[o_temp_view superview] convertRect: [o_temp_view frame] toView: nil]; /* Convert to Window base coord */
    frame.origin.x += [self frame].origin.x; 
    frame.origin.y += [self frame].origin.y;

    dict2 = [[NSMutableDictionary alloc] initWithCapacity:2];
    [dict2 setObject:self forKey:NSViewAnimationTargetKey];
    [dict2 setObject:NSViewAnimationFadeInEffect forKey:NSViewAnimationEffectKey];

    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict2, nil]];
    [dict2 release];

    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.3];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict1 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict1 setObject:[NSValue valueWithRect:frame] forKey:NSViewAnimationEndFrameKey];

    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict1, nil]];
    [dict1 release];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.2];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];
    [o_fullscreen_anim1 startAnimation];
}

- (void)hasEndedFullscreen
{
    /* This function is private and should be only triggered at the end of the fullscreen change animation */
    /* Make sure we don't see the o_view disappearing of the screen during this operation */
    DisableScreenUpdates();
    [o_view retain];
    [o_view removeFromSuperviewWithoutNeedingDisplay];
    [[self contentView] replaceSubview:o_temp_view with:o_view];
    [o_view release];
    [o_view setFrame:[o_temp_view frame]];
    [self makeKeyAndOrderFront:self];
    [o_fullscreen_window orderOut: self];
    EnableScreenUpdates();

    [o_fullscreen_window release];
    o_fullscreen_window = nil;
}

- (void)animationDidEnd:(NSAnimation*)animation
{
    NSArray *viewAnimations;

    if ([animation currentValue] < 1.0)
        return;

    /* Fullscreen ended or started (we are a delegate only for leaveFullscreen's/enterFullscren's anim2) */
    viewAnimations = [o_fullscreen_anim2 viewAnimations];
    if ([viewAnimations count] >=1 &&
        [[[viewAnimations objectAtIndex: 0] objectForKey: NSViewAnimationEffectKey] isEqualToString:NSViewAnimationFadeInEffect])
    {
        /* Fullscreen ended */
        [self hasEndedFullscreen];
    }
    else
    {
        /* Fullscreen started */
        [self hasBecomeFullscreen];
    }
}

@end
