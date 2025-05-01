let response = "";
let decryptor = 7983442720963060024057948886542171092952310290025484363884501439;
if (secrets.decryptor) {
  decryptor = secrets.decryptor;
}

const _RandomnessSeed = args[0];
const _numProphets = args[1];
const _action = args[2];
const _currentProphetTurn = args[3];
const _ticketShare = args[4]; //This is a whole number percent (0%-100%)

// Note, largest Number JS can Modulo is ~16 digits, after which this will always return '0'
// We will need a very large number for encryptor to divide RandomnessSeed by since
// RandomnessSeed is usually large uint256 number
// There may need to be error catching to revert contract back to prior state

// Determine who the Chosen One is
const chosenOne = Math.floor((_RandomnessSeed / decryptor) % _numProphets);
console.log(`chosenOne = ${chosenOne}`);

// action == 0 then attempt miracle"
// return '1' if successful and '0' if unsuccessful
if (_action == 0) {
  const miracleFailureOdds = 25;
  let result = "1";
  if (_currentProphetTurn != chosenOne) {
    if (
      1 + ((Math.random() * 100) % 100) + _ticketShare / 10 <
      miracleFailureOdds
    )
      result = "0";
  }
  response = response.concat(result);
}
// action == 1 then attempt to smite
// return '3' if successful and '2' if unsuccessful
else if (_action == 1) {
  const smiteFailureOdds = 90;
  let result = "3";
  if (_currentProphetTurn != chosenOne) {
    if (1 + ((Math.random() * 100) % 100) + _ticketShare / 2 < smiteFailureOdds)
      result = "2";
  }
  response = response.concat(result);
}

// action == 2 then accuse of Blasphemy
// return '5' if successful and '4' if unsuccessful
else if (_action == 2) {
  const accuseFailureOdds = 90;
  let result = "5";
  if (1 + ((Math.random() * 100) % 100) + _ticketShare < accuseFailureOdds) {
    result = "4";
  }
  response = response.concat(result);
}

// if action == 3 then startGame() called
// Returns a string of 1's and 0's indicating alive and dead for the prophet in each position of the string
else if (_action == 3) {
  for (let _prophet = 0; _prophet < _numProphets; _prophet++) {
    const miracleFailureOdds = 25;
    let result = "1";
    if (_prophet != chosenOne) {
      if (1 + ((Math.random() * 100) % 100) < miracleFailureOdds) result = "0";
    }
    response = response.concat(result);
  }
}

console.log(`response = ${response}`);
return Functions.encodeString(response);
