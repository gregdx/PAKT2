import Foundation
import SwiftUI

// MARK: - Localization (English only)

enum L10n {
    /// Translation by key
    static func t(_ key: String) -> String {
        strings[key] ?? key
    }

    // MARK: - Strings

    private static let strings: [String: String] = [

        // General
        "save":                 "Save",
        "done":                 "Done",
        "cancel":               "Cancel",
        "delete":               "Delete",
        "loading":              "Loading...",
        "error":                "Error",
        "offline":              "No connection",
        "golden_rule":          "under 3h per day",
        "password_hint":        "6 characters minimum",
        "welcome_empty_title":  "Challenge your friends",
        "welcome_empty_desc":   "Create a group and invite your friends\nto see who can spend the least time on their phone.",

        // Onboarding walkthrough
        "skip":                 "skip",
        "ob_time_title":        "Your time is precious",
        "ob_time_desc":         "The average person spends\n4 hours a day on their phone.\nThat's 60 full days per year.",
        "ob_friends_title":     "Do it with friends",
        "ob_friends_desc":      "Create a group, invite your friends,\nand see who can spend\nthe least time on their phone.",
        "ob_challenge_title":   "Challenge each other",
        "ob_challenge_desc":    "Competitive or collective mode.\nThe loser buys a round.\nStay under your goal to win.",
        "ob_track_title":       "100% automatic",
        "ob_track_desc":        "PAKT reads your screen time\nautomatically. No manual input.\nYour data stays private.",

        // Onboarding
        "get_started":          "get started",
        "tagline":              "A pakt between friends\nthat could change your life.",
        "already_account":      "I already have an account",
        "data_privacy":         "Your data is only shared\nwith your group members.",
        "create_account":       "Create account",
        "welcome_back":         "Welcome back",
        "sign_in":              "Sign in",
        "sign_in_instead":      "Sign in instead",
        "create_instead":       "Create account",
        "first_name":           "First name",
        "email":                "Email",
        "password":             "Password",
        "continue":             "Continue",
        "or":                   "or",
        "username_taken":       "this username is already taken",
        "accept_terms_prefix":  "I accept the ",
        "terms_of_use":         "Terms of Use",
        "accept_terms_and":     " and the ",

        // Permissions
        "screen_time_access":   "Screen time access",
        "screen_time_desc":     "PAKT reads your screen time automatically\nso you don't have to enter it manually.\nonly your groups can see it.",
        "total_time_day":       "total time per day — automatic",
        "history_7_30":         "7 and 30 day history",
        "no_app_names":         "we never see which apps you use",
        "group_only":           "visible only to your group",
        "allow_access":         "allow access",
        "enter_manually":       "Enter manually instead",
        "perm_denied":          "permission denied — you can enable it later in Settings",

        // Today
        "yesterday":            "yesterday",
        "goal_reached":         "goal reached",
        "goal_not_reached":     "goal not reached",
        "over_goal":            "over goal",
        "under_goal":           "under goal",
        "no_data_yet":          "No data yet",
        "day_streak":           "day streak",
        "under_goal_streak":    "under your daily goal",
        "my_challenges":        "my challenges",

        // Profile
        "friends":              "Friends",
        "enter_score":          "enter yesterday's screen time",
        "update_score":         "update yesterday's score",
        "synced_auto":          "screen time synced automatically",
        "waking_day":           "of your waking day",
        "waking_day_screens":   "of your waking day on screens",
        "under_goal_keep":      "under your goal — keep it up",
        "days_wasted":          "full days wasted per year at this pace",
        "week_avg":             "week avg",
        "month_avg":            "month avg",
        "active_challenges":    "my active challenges",
        "no_challenges":        "No active challenges",
        "days_remaining":       "days remaining",
        "last_day":             "last day",
        "rank":                 "rank",
        "you":                  "you",

        // Groups
        "groups":               "Groups",
        "create_group":         "Create a group",
        "join_group":           "Join a group",
        "enter_code":           "Enter group code",
        "join":                 "Join",
        "group_name":           "Group name",
        "competitive":          "Competitive",
        "collective":           "Collective",
        "comp_desc":            "lowest screen time wins",
        "coll_desc":            "group average must meet goal",
        "daily_goal":           "Daily goal",
        "duration":             "duration",
        "1_day":                "1 day",
        "1_week":               "1 week",
        "2_weeks":              "2 weeks",
        "1_month":              "1 month",
        "members":              "members",
        "leave_group":          "Leave group",
        "share_code":           "Share code",

        // Daily score
        "yesterdays_st":        "yesterday's screen time",
        "auto_tracking_on":     "automatic tracking is on — use this for manual override",
        "check_settings":       "Settings → Screen Time → scroll to Yesterday",
        "goal_done":            "goal reached — well done",
        "goal_not_done":        "goal not reached this time",
        "full_days_year":       "full days per year",

        // Settings
        "settings":             "Settings",
        "daily_st_goal":        "DAILY SCREEN TIME GOAL",
        "waking_pct":           "of your waking day",
        "save_goal":            "Save goal",
        "saved":                "Saved",
        "appearance":           "APPEARANCE",
        "dark_mode":            "Dark mode",
        "language":             "Language",
        "username":             "USERNAME",
        "account":              "ACCOUNT",
        "sign_out":             "Sign out",
        "available":            "available",
        "already_taken":        "already taken",
        "checking":             "checking...",

        // Settings (extended)
        "profile":              "Profile",
        "preferences":          "PREFERENCES",
        "support":              "SUPPORT",
        "edit_photo":           "edit photo",
        "screen_time_status":   "screen time",
        "connected":            "connected",
        "not_connected":        "not connected",
        "open_screen_time_settings": "Open Screen Time settings",
        "privacy_policy":       "Privacy policy",
        "help_feedback":        "Help & feedback",
        "version":              "version",
        "delete_account":       "Delete account",
        "delete_account_warn":  "This will permanently delete your account and all your data. This action cannot be undone.",
        "confirm_delete":       "yes, delete everything",
        "pause_account":        "pause my account",
        "confirm_password":     "confirm your password",
        "reenter_password_desc": "Enter your password to permanently delete your account.",

        // Friends
        "incoming_requests":    "incoming requests",
        "my_friends":           "my friends",
        "search_friends":       "search friends",
        "add_friend":           "add friend",
        "remove":               "Remove",
        "accept":               "Accept",
        "decline":              "Decline",

        // Notifications
        "notifications":        "Notifications",
        "group_invite":         "invited you to join",

        // Scope
        "scope_total":          "total screen time",
        "scope_total_desc":     "ranking based on total daily screen time",
        "scope_social":         "social media only",
        "scope_social_desc":    "ranking based on social media time only — Instagram, TikTok, etc.",

        // Categories
        "social":               "social",
        "on_social_media":      "on social media",
        "social_goal":          "SOCIAL MEDIA GOAL",
        "utilities":            "utilities",
        "entertainment":        "entertainment",
        "other":                "other",

        // Activities
        "instead_of_scrolling": "INSTEAD OF SCROLLING",
        "all":                  "all",
        "cat_outdoor":          "outdoor",
        "cat_food":             "food",
        "cat_creative":         "creative",
        "cat_sport":            "sport",
        "cat_chill":            "chill",
        "cat_social":           "social",

        // Activities
        "activities_title":     "Messages",
        "activities_subtitle":  "Find a mate to stop scrolling",
        "tab_friends":          "Friends",
        "tab_near_you":         "Near you",
        "near_you_title":       "Discover",
        "near_you_coming":      "Coming soon",
        "near_you_desc":        "Activities from local spots\nnear you — cafés, gyms, parks...",
        "visit_website":        "Website",
        "go_with_friend":       "Go with a friend",
        "no_venues_radius":     "No spots in this radius",
        "allow_location":       "Enable location",
        "location_needed":      "To see what's near you",
        "chat_expires":         "This chat resets in 24h",
        "member_since":         "Member since",
        "propose_activity":     "PROPOSE AN ACTIVITY",
        "incoming_proposals":   "INCOMING",
        "sent_proposals":       "SENT",
        "proposal_sent":        "Proposal sent",
        "send_proposal":        "Send",
        "no_conversations_yet": "No conversations yet",
        "start_conversation":   "New conversation",
        "send_first_activity":  "Send an activity to get started",
        "propose_activity_short": "Propose an activity",
        "type_message":         "Message...",
        "proposal_mine":        "How about {activity}?",
        "proposal_theirs":      "Wants to {activity}",
        "resp_lets_go":         "Let's go!",
        "resp_cant_now":        "Can't rn",
        "resp_rather_scroll":   "I'd rather scroll",
        "accepted":             "accepted",
        "no_friends_yet":       "No friends yet",
        "add_friends_first":    "Add friends to propose activities",
        "act_walk":             "Walk",
        "act_run":              "Run",
        "act_hike":             "Hike",
        "act_bike":             "Bike ride",
        "act_gym":              "Gym",
        "act_tennis":           "Tennis",
        "act_basketball":       "Basketball",
        "act_swim":             "Swim",
        "act_coffee":           "Coffee",
        "act_brunch":           "Brunch",
        "act_cook":             "Cook",
        "act_dinner":           "Dinner",
        "act_board_game":       "Board game",
        "act_read":             "Read",
        "act_draw":             "Draw",
        "act_music":            "Music",
        "act_park":             "Park",
        "act_picnic":           "Picnic",
        "act_movie":            "Movie",
        "act_sunset":           "Sunset",

        // Create group
        "new_group":            "New group",
        "group_name_label":     "GROUP NAME",
        "game_mode":            "GAME MODE",
        "tracked_time":         "TRACKED TIME",
        "per_day_max":          "per day maximum",
        "waking_day_pct":       "of a 16h waking day",
        "group_created":        "group created",
        "invite_code":          "INVITE CODE",
        "copy_code":            "copy code",
        "view_my_group":        "view my group",
        "comp_desc_long":       "ranking — the worst performer buys a round",
        "coll_desc_long":       "together — the group average must stay on target",
        "comp_goal_desc":       "everyone must stay under — the ranking determines the loser",
        "coll_goal_desc":       "the group average must stay under this limit",
        "challenge_duration":   "challenge duration",
        "create_group_btn":     "Create group",
        "mode_label":           "mode",
        "tracked_label":        "tracked",
        "days_count":           "days",

        // Join group
        "group_code":           "Group code",
        "searching":            "Searching...",
        "joined_group":         "you joined the group",
        "already_in":           "you're already in this group",
        "group_not_found":      "no group found with this code",
        "something_wrong":      "something went wrong",
        "lets_go":              "let's go",

        // Group detail
        "final_ranking":        "final ranking",
        "final_ranking_desc":   "This ranking determines the winner at the end of the challenge",
        "time_spent":           "total time",
        "this_week":            "THIS WEEK",
        "overview":             "OVERVIEW",
        "group_avg":            "GROUP AVG",
        "best":                 "BEST",
        "under_goal_label":     "UNDER GOAL",
        "comparison":           "COMPARISON",
        "over_goal_label":      "over goal",
        "progress":             "PROGRESS",
        "completed":            "completed",
        "pct_waking":           "of your waking day",

        // Edit group
        "edit_group":           "Edit group",
        "challenge_settings":   "CHALLENGE SETTINGS",
        "settings_locked":      "challenge settings cannot be changed once started",
        "group_code_label":     "GROUP CODE",
        "copied":               "copied!",
        "copy":                 "copy",
        "share_code_desc":      "share this code so friends can join",
        "invite_friends":       "INVITE FRIENDS",
        "invited_check":        "invited ✓",
        "invite_btn":           "invite",
        "cancel_invite":        "cancel",
        "delete_group":         "delete group",
        "delete_group_warn":    "This will permanently remove the group for all members.",
        "leave_group_warn":     "You'll be removed from the group. Other members won't be affected.",
        "save_changes":         "save changes",

        // Friends
        "friends_title":        "Friends",
        "friends_subtitle":     "Add friends to challenge them",
        "friend_requests":      "friend requests",
        "wants_friend":         "wants to be your friend",
        "no_friends":           "No friends yet — search by username below",
        "find_username":        "find by username",
        "username_ph":          "username...",
        "no_user_found":        "No user found",
        "from_contacts":        "from your contacts",
        "no_contacts":          "None of your contacts are on PAKT yet",
        "find_contacts":        "find friends from contacts",
        "invite_friend":        "invite a friend",
        "copy_invite":          "copy invite link",
        "share_via":            "share via iMessage, WhatsApp...",
        "friends_check":        "friends ✓",
        "request_sent":         "request sent",
        "add_friend_btn":       "add friend",

        // Notifications
        "group_invitations":    "group invitations",
        "no_notifs":            "No notifications",
        "no_notifs_desc":       "When a friend invites you to a group,\nyou'll see it here.",
        "invited_to_group":     "invited you to join a group",
        "join_group_btn":       "join group",
        "just_now":             "just now",

        // Member profile
        "no_data_today":        "No data today",
        "waking_screens_avg":   "of waking day on screens (final avg)",
        "days_lost_year":       "full days lost per year at this rate",
        "years_in_lifetime":    "years of a lifetime (80y)",
        "today_label":          "TODAY",
        "since_start":          "FINAL",
        "group_goal":           "GROUP GOAL",
        "per_day_max_label":    "per day maximum",
        "days_under":           "days under goal",
        "days_over":            "days over goal",
        "today_excluded":       "today excluded",
        "avg_since_start":      "final average",

        // Challenge result
        "challenge_complete":   "challenge complete",
        "challenge_failed":     "challenge failed",
        "wins_challenge":       "wins the challenge",
        "whats_next":           "WHAT'S NEXT",
        "restart_same":         "restart same challenge",
        "new_challenge_started": "new challenge started",
        "start":                "start",
        "name_new_challenge":   "name the new challenge",

        // Username
        "choose_username":      "Choose your name",
        "choose_username_desc": "This is how your friends will see you.\nIt must be unique.",

        // Email verification
        "verify_email":         "Verify your email",
        "verify_email_desc":    "We sent a 6-digit code to your email.\nEnter it below to verify your account.",
        "i_verified":           "I've verified my email",
        "resend_email":         "Resend code",
        "email_not_verified":   "Invalid or expired code",
        "today":                "today",

        // Medals
        "medals":               "MEDALS",
        "rules":                "RULES",
        "rules_desc":           "The player with the lowest screen time at the end of the challenge wins a medal.",

        // Chart
        "day":                  "Day",
        "week":                 "Week",
        "month":                "Month",
        "goal":                 "goal",

        // Period
        "period_final":         "Final",
        "period_day":           "Day",

        // Streak
        "streak_explanation":   "stay under 3h to earn streaks",
        "streak_explanation_long": "Stay under the limit for several consecutive days to start a streak. The longer your streak, the better.",

        // Misc
        "per_day":              "/day",
        "members_count":        "members",
        "days_left":            "days left",

        // Stakes
        "stake_title":              "What's at stake?",
        "stake_label":              "STAKE",
        "stake_for_fun":            "For fun",
        "stake_last_pays":          "Last pays a round",
        "stake_dinner":             "Dinner",
        "stake_custom":             "Custom",
        "stake_custom_placeholder": "Write your stake...",

        // Required players
        "required_players_title":   "How many players?",
        "required_players":         "required players",
        "players_needed":           "players to start",
        "players_needed_desc":      "The pakt starts when this many\npeople have signed — including you",

        // Pakt status
        "status_pending":           "pending",
        "status_active":            "active",
        "pending_pakts":            "WAITING FOR SIGNATURES",
        "active_pakts":             "ACTIVE PAKTS",
        "finished_pakts":           "FINISHED",
        "delete_pakt":              "Delete pakt",
        "signatures":               "signatures",
        "waiting_signatures":       "Waiting for signatures",
        "waiting_signature":        "waiting...",
        "signatures_needed_desc":   "Share the code with your friends.\nThe pakt starts as soon as everyone signs.",
        "pakt_created":             "Pakt created",
        "pakt_activated":           "The pakt has started!",
        "sign_the_pakt":            "Sign the pakt",

        // Empty states
        "search_or_invite":         "Search by username or invite a friend",
        "all_caught_up":            "You're all caught up!",
        "pending_invitations":      "pending invitations",

        // Group chat
        "sent":                     "Sent",
        "no_messages_yet":          "No messages yet",

        // Invite
        "invite_message":           "Join me on PAKT! Download the app and use my group code:",

        // Group list / detail
        "starts_midnight":          "Starts at midnight",
        "challenge_begins_midnight": "The challenge will begin at 00:00.\nEveryone's score starts fresh tomorrow.",

        // Context menus
        "archive":                  "Archive",
        "unarchive":                "Unarchive",
        "delete_for_me":            "Delete for me",
        "delete_for_everyone":      "Delete for everyone",

        // Activities
        "no_archived_conversations": "No archived conversations",

        // Members
        "see_all":                  "See all",
        "admin":                    "Admin",

        // Create group
        "start_now":                "Start now",
        "start_time":               "START TIME",
        "at_midnight":              "At 00:00",

        // Charts
        "details":                  "details",

        // Challenge result slides
        "the_winner":               "THE WINNER",
        "avg_per_day":              "average per day",
        "goal_reached_title":       "GOAL\nREACHED",
        "goal_not_reached_title":   "GOAL\nNOT REACHED",
        "group_crushed_it":         "Your group crushed it.",
        "better_luck":              "Better luck next time.",
        "final_ranking_title":      "FINAL RANKING",
        "best_day":                 "BEST DAY",
        "least_st_day":             "Least screen time\nin a single day",
        "screen_time_label":        "screen time",
        "no_data_recorded":         "No data recorded",
        "worst_day":                "WORST DAY",
        "most_st_day":              "Most screen time\nin a single day",
        "your_group":               "YOUR GROUP",
        "in_numbers":               "in numbers",
        "players":                  "PLAYERS",
        "days_label":               "DAYS",
        "daily_goal_label":         "DAILY GOAL",
        "group_average":            "GROUP AVERAGE",
        "ready_another":            "READY FOR\nANOTHER ONE?",
        "same_group_new":           "Same group, new challenge.",
        "restart_challenge":        "Restart same challenge",
        "harder_goal":              "Harder goal",
        "swipe_to_explore":         "Swipe to explore",
        "new_challenge_btn":        "Start",
        "name_challenge":           "Name the new challenge",
    ]
}
