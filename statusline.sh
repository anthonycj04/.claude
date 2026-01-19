#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract model information
MODEL=$(echo "$input" | jq -r '.model.display_name')

# Fetch OAuth token from macOS Keychain
TOKEN_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
if [ -n "$TOKEN_JSON" ]; then
    ACCESS_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.claudeAiOauth.accessToken' 2>/dev/null)

    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        # Fetch usage limits from API
        USAGE_DATA=$(curl -s -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "User-Agent: claude-code/2.0.31" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

        if [ -n "$USAGE_DATA" ]; then
            # Extract 5-hour utilization and reset time
            UTILIZATION=$(echo "$USAGE_DATA" | jq -r '.five_hour.utilization // 0' | cut -d. -f1)
            RESETS_AT=$(echo "$USAGE_DATA" | jq -r '.five_hour.resets_at // empty')

            # Extract 7-day utilization and reset time
            WEEKLY_UTILIZATION=$(echo "$USAGE_DATA" | jq -r '.seven_day.utilization // 0' | cut -d. -f1)
            WEEKLY_RESETS_AT=$(echo "$USAGE_DATA" | jq -r '.seven_day.resets_at // empty')

            # Calculate 5-hour time remaining
            FIVE_HOUR_TIME=""
            if [ -n "$RESETS_AT" ] && [ "$RESETS_AT" != "null" ]; then
                RESET_CLEAN=$(echo "$RESETS_AT" | sed 's/\.[0-9]*+.*//')
                RESET_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESET_CLEAN" "+%s" 2>/dev/null)
                CURRENT_EPOCH=$(date +%s)
                TIME_DIFF=$((RESET_EPOCH - CURRENT_EPOCH))

                if [ $TIME_DIFF -gt 0 ]; then
                    HOURS=$((TIME_DIFF / 3600))
                    MINUTES=$(((TIME_DIFF % 3600) / 60))
                    FIVE_HOUR_TIME="${HOURS}h${MINUTES}m"
                fi
            fi

            # Calculate weekly time remaining
            WEEKLY_TIME=""
            if [ -n "$WEEKLY_RESETS_AT" ] && [ "$WEEKLY_RESETS_AT" != "null" ]; then
                WEEKLY_RESET_CLEAN=$(echo "$WEEKLY_RESETS_AT" | sed 's/\.[0-9]*+.*//')
                WEEKLY_RESET_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$WEEKLY_RESET_CLEAN" "+%s" 2>/dev/null)
                CURRENT_EPOCH=$(date +%s)
                WEEKLY_TIME_DIFF=$((WEEKLY_RESET_EPOCH - CURRENT_EPOCH))

                if [ $WEEKLY_TIME_DIFF -gt 0 ]; then
                    DAYS=$((WEEKLY_TIME_DIFF / 86400))
                    HOURS=$(((WEEKLY_TIME_DIFF % 86400) / 3600))
                    MINUTES=$(((WEEKLY_TIME_DIFF % 3600) / 60))
                    WEEKLY_TIME="${DAYS}d${HOURS}h${MINUTES}m"
                fi
            fi

            # Output formatted statusline with both 5-hour and weekly usage
            if [ -n "$FIVE_HOUR_TIME" ] || [ -n "$WEEKLY_TIME" ]; then
                printf '\033[38;5;4m[%s]\033[0m usage: \033[38;5;3m%d%%\033[0m (\033[38;5;6m%s\033[0m) weekly: \033[38;5;3m%d%%\033[0m (\033[38;5;6m%s\033[0m)' \
                    "$MODEL" "$UTILIZATION" "${FIVE_HOUR_TIME:---h--m}" "$WEEKLY_UTILIZATION" "${WEEKLY_TIME:---d--h--m}"
                exit 0
            fi
        fi
    fi
fi

# Fallback if API call fails
printf '\033[38;5;4m[%s]\033[0m usage: \033[38;5;3m--%%\033[0m (\033[38;5;6m--h--m\033[0m)' "$MODEL"