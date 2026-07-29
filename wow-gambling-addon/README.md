# CasinoHost

A World of Warcraft addon for **hosting gold-gambling games**. Built for the host
(you) to run games in party/say/channel chat, announce bets automatically, run a
roll-based blackjack table, and track a points/loyalty system players can redeem.

## What it does

### 1. Trade-bet announcer
When a player trades you gold and the trade completes, CasinoHost announces it for
everyone to see:

> **Bob just bet 500g!**

No macro needed - it reads the trade automatically, awards the player points for
the bet, and **whispers them their new points balance** right away:

> Bet received: 500g (+500 points). Balance: 1250 points. Whisper !redeem &lt;amount&gt; to cash in.

### 2. Roll blackjack (target 100)
Players `/roll` (1-100) in the party. Each roll adds to their running total; get as
close to **100** as you can. Over 100 = **bust**. Type `stand` in chat to hold.

CasinoHost narrates the whole thing:

> Bob just rolled 47 - total 47.
> Bob just rolled 39 - total 86.
> Bob stands on 86.
> Sue just rolled 61 - total 108. **BUST!**
> **Bob wins with 86!**

### 3. Points & redemptions
Betting earns points (default: 1 point per gold bet, configurable). Players whisper
you:

- `!balance` -> *"You have 500 point(s)."*
- `!redeem 100` -> deducts points and adds a redemption to your queue to fulfil.
- `!help` -> lists the commands.

### 4. Trade logger / P&L
Every gold trade is logged both ways: gold coming **in** (bets) and gold going
**out** (payouts you trade back). The **P&L** tab shows session and all-time
profit, plus a per-player breakdown of who's up and who's down against the house.
`/casino session reset` zeroes the session counter at the start of a hosting
night; paid someone by mail instead of trade? `/casino payout <name> <gold>`.

## Install
1. Copy the `CasinoHost` folder into
   `World of Warcraft\_retail_\Interface\AddOns\`.
2. Restart WoW (or `/reload`). Make sure CasinoHost is enabled on the character
   select AddOns list.

> Interface version is set for retail (11.2). For Classic, edit the first line of
> `CasinoHost.toc` to your client's interface number.

## Commands (`/casino` or `/ch`)
| Command | Description |
|---|---|
| `/casino` | Open/close the window |
| `/casino bj start` | Open a blackjack round |
| `/casino bj stop` | Close the round (no more rolls) |
| `/casino bj result` | Announce the winner |
| `/casino bj clear` | Clear the table |
| `/casino channel <party\|say\|raid\|guild\|yell\|channel NAME>` | Where to announce |
| `/casino rate <n>` | Points per gold bet |
| `/casino dryrun on\|off` | Test announcements locally (no chat spam) |
| `/casino points [name]` | Show a balance or the leaderboard |
| `/casino give <name> <points>` | Manually adjust points |
| `/casino bet <name> <gold>` | Manually log a bet (if you didn't trade) |
| `/casino pl` | Print session + all-time profit/loss |
| `/casino session [reset]` | Show session P&L, or start a new session |
| `/casino payout <name> <gold>` | Manually log a payout (mail, COD, etc.) |
| `/casino redemptions` | List pending redemptions |
| `/casino fulfill <n>` | Clear a redemption from the queue |
| `/casino reset confirm` | Wipe all points, redemptions and logs |

## Announcing to everyone (not just your party)
By default announcements go to **party** chat. Switch with
`/casino channel say` (everyone nearby), `yell` (bigger radius), or `guild`.

Note: Blizzard blocks addons from auto-sending `/say` and `/yell` - a real
click is required. When you use say/yell, CasinoHost queues each announcement
on a big **"Announce: ..."** button at the top of your screen; one click sends
it. (Right-click-drag moves the button.) Party/raid/guild/custom channels send
instantly.

## Tip
Turn on **dry-run** (`/casino dryrun on`) to try everything solo - announcements
print only to your own chat so you can rehearse before going live.

## Status
Trade announcer (with auto balance whisper), blackjack, points/redemptions, and
the P&L trade logger are all implemented. Ideas for later: deathroll and
coinflip/dice side games.
