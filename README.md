# Phenomenon - Become a Movement

Gain followers, smite your enemies, and shun the nonbelievers. Be part of the Phenomenon!

## Game Frontend URL

[https://0xomen.github.io/phenomenon/](https://0xomen.github.io/phenomenon/)

# Rules of Phenomenon

Requires 4 to 9 starting players. However, once the game is started an unlimited amount of participants are allowed.

Players register to become prophets. A prophet wins by being the last prophet alive.

One prophet is randomly selected to be the Chose One. The Chose One has divine powers and will never fail to perform a miracle or smite another player.

No one knows who the Chosen One is, not even the Chosen One. Players must deduce this through game play.

When it is a prophet's turn they can do one of three actions: Perform Miracle, Attempt to Smite, and Accuse of Blasphemy.

## Perform Miracle

Perform a Miracle to show divinity. The Chosen One will always successfully perform a miracle. Other Prophets start with a 75% chance of successfully performing a miracle, odds improve with a higher percentage of followers they have. Failing to perform a miracle results in elimination. Completing a miracle frees a Prophet if jailed and ends a Prophet's turn.

## Attempt to Smite

Smite another Prophet to prove your power. The Chosen One will always successfully smite an opponent. Other Prophets start with a 10% chance of successfully smiting an opponent and their odds improve with a higher percentage of followers. Failure to smite results in being jailed.

## Accuse of Blasphemy

A successful accusation has 2 possible outcomes: if the target opponent is free, then they are placed in jail -or- if the target opponent is already in jail then they are executed and eliminated from the game. The Chosen One has no advantage with this action. Prophets start with a 10% chance of success and odds improve with the greater percentage of followers they have. A successful accusation puts a free Prophet in jail or eliminates an already jailed Prophet. Failure to accuse results in the accuser being jailed. Jailed Prophets cannot Accuse.

## High Priests

At the start of the game, some prophets may randomly be chosen as High Priests. These players cannot win the game on their own, however if they are the High Priest of the last remaining prophet, then the High Priest also wins. Prophets with High Priests have improved odds of succesful actions. If the prophet that the High Priest is supporting dies, then the High Priest is also eliminated. High Priests may change who they support at any time (excluding the time waiting for a Chainlink Function callback) as long as they have not been eliminated. Changing allegiance is free for High Priests.

## Anti-Griefing - Force Turn

If after a certain period of time a player has not taken their turn, ANYONE may force them to perform a miracle by clicking the Force Miracle button.

## Acolytes

Anyone who is not a Prophet or High Priest can participate and affect the game by buying Tickets to Valhalla of a Prophet, thus becoming an Acolyte. Acolytes can only hold tickets of one Prophet at a time. To change allegiance from one prophet to another, they must first sell all tickets of the initial prophet they are following.

## Tickets to Valhalla

Holding tickets of the last prophet remaining entitles the ticket holder to a proportional amount of the prize pool. Holding tickets to a Prophet when the Prophet gets eliminated results in the tickets becoming worthless and the Acolyte being eliminated from the game.

## Buying/Selling Tickets

Tickets to Valhalla are bought and sold on a bonding curve for each Prophet. The fewer Tickets in circulation for a Prophet, the lower the price to buy or sell that Prophet's ticket. To change allegiance from one Prophet to another, an Acolyte must first sell all of their tickets from their original Prophet.

## Ending and Reseting Game

When only one prophet remains, the winners can claim their share of the tokens in the pot. After everyone has claimed their tokens, reset the game with the desired number of players for the next round. Must wait 6 minutes to reset game.

---

## Developer Notes – GameplayEngine (Chainlink Functions)

### Production vs Testing

- **Production:** `startGame` is `private`; line 317 `_sendRequest` is **uncommented** (calls real Chainlink Functions Router).
- **Testing:** `startGame` is `internal`; line 317 `_sendRequest` is **commented out** so tests can use GameplayEngineHelper/mocks without hitting the real router.

### Gas Limit (Base Sepolia / Base Mainnet)

Chainlink Functions subscriptions use a default tier that allows max **300,000** callback gas. The default `gasLimit` of 750,000 exceeds this and causes reverts on `sendRequest`.

After deploying to Base Sepolia or Base Mainnet, call `changeGasLimit(300000)` on the GameplayEngine contract. Example: [Base Sepolia tx](https://sepolia.basescan.org/tx/0xd46938e2489ae1ab03a2d96a87bcf8b64c3ee62dc86bcaa9b818bf0721e6c234).
