// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockFunctionsRouter
 * @notice Mock contract that simulates Chainlink Functions Router for testing
 * @dev This contract mocks the Chainlink Functions Router interface needed by GameplayEngine
 */
contract MockFunctionsRouter {
    error InvalidCallbackGasLimit(uint32 callbackGasLimit);
    error OnlyRouterCanFulfill();
    error InvalidRequestID(bytes32 requestId);
    error EmptyRequestData();

    struct Request {
        address requester;
        address callbackAddr;
        bytes4 callbackFunctionId;
        uint32 callbackGasLimit;
        uint96 estimatedTotalCostJuels;
        bytes requestData;
        bytes32 donId;
        bool fulfilled;
        bytes response;
        bytes error;
    }

    // Storage variables
    mapping(bytes32 => Request) private s_requests;
    bytes32[] private s_requestIds;
    mapping(uint64 => uint96) private s_subscriptionBalances;
    mapping(uint64 => address) private s_subscriptionOwners;
    mapping(uint64 => address[]) private s_consumers;
    uint64 private s_currentSubscriptionId;
    uint256 private s_currentRequestId;

    // Events
    event RequestSent(
        bytes32 indexed id, uint64 indexed subscriptionId, bytes data, uint32 callbackGasLimit, bytes32 donId
    );
    event RequestFulfilled(bytes32 indexed id, bytes response, bytes error);
    event SubscriptionCreated(uint64 indexed subscriptionId, address owner);
    event SubscriptionConsumerAdded(uint64 indexed subscriptionId, address consumer);
    event SubscriptionFunded(uint64 indexed subscriptionId, uint256 oldBalance, uint256 newBalance);

    constructor() {
        s_currentSubscriptionId = 1;
        s_currentRequestId = 0;
    }

    /**
     * @notice Create a new subscription
     * @return subscriptionId The newly created subscription ID
     */
    function createSubscription() external returns (uint64) {
        uint64 subscriptionId = s_currentSubscriptionId++;
        s_subscriptionOwners[subscriptionId] = msg.sender;
        s_subscriptionBalances[subscriptionId] = 0;

        emit SubscriptionCreated(subscriptionId, msg.sender);
        return subscriptionId;
    }

    /**
     * @notice Add a consumer to a subscription
     * @param subscriptionId The subscription ID
     * @param consumer The consumer address to add
     */
    function addConsumer(uint64 subscriptionId, address consumer) external {
        require(s_subscriptionOwners[subscriptionId] == msg.sender, "Not subscription owner");
        s_consumers[subscriptionId].push(consumer);

        emit SubscriptionConsumerAdded(subscriptionId, consumer);
    }

    /**
     * @notice Fund a subscription with LINK tokens
     * @param subscriptionId The subscription ID
     * @param amount The amount to fund
     */
    function fundSubscription(uint64 subscriptionId, uint96 amount) external {
        uint96 oldBalance = s_subscriptionBalances[subscriptionId];
        s_subscriptionBalances[subscriptionId] += amount;

        emit SubscriptionFunded(subscriptionId, oldBalance, s_subscriptionBalances[subscriptionId]);
    }

    /**
     * @notice Get the current balance of a subscription
     * @param subscriptionId The subscription ID
     * @return The current balance
     */
    function getSubscriptionBalance(uint64 subscriptionId) external view returns (uint96) {
        return s_subscriptionBalances[subscriptionId];
    }

    /**
     * @notice Simulates sending a request to the Chainlink Functions network
     * @param requestData The CBOR-encoded request data
     * @param subscriptionId The subscription ID to charge for the request
     * @param callbackGasLimit The gas limit for the callback function
     * @param donId The DON ID
     * @return requestId The ID of the sent request
     */
    function sendRequest(bytes calldata requestData, uint64 subscriptionId, uint32 callbackGasLimit, bytes32 donId)
        external
        returns (bytes32)
    {
        // Generate a unique requestId
        bytes32 requestId = keccak256(abi.encode(s_currentRequestId++, msg.sender, requestData, block.timestamp));

        // Store the request
        Request memory request = Request({
            requester: msg.sender,
            callbackAddr: msg.sender,
            callbackFunctionId: bytes4(keccak256("fulfillRequest(bytes32,bytes,bytes)")),
            callbackGasLimit: callbackGasLimit,
            estimatedTotalCostJuels: 0,
            requestData: requestData,
            donId: donId,
            fulfilled: false,
            response: new bytes(0),
            error: new bytes(0)
        });

        s_requests[requestId] = request;
        s_requestIds.push(requestId);

        emit RequestSent(requestId, subscriptionId, requestData, callbackGasLimit, donId);
        return requestId;
    }

    /**
     * @notice Mocks the Chainlink Functions network sending a response
     * @param requestId The request ID to fulfill
     * @param response The response to send
     * @param err Any error to send
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) external {
        Request storage request = s_requests[requestId];

        require(request.requester != address(0), "Request not found");
        require(!request.fulfilled, "Request already fulfilled");

        request.fulfilled = true;
        request.response = response;
        request.error = err;

        (bool success,) =
            request.callbackAddr.call(abi.encodeWithSelector(request.callbackFunctionId, requestId, response, err));

        // In a real scenario, we would handle this differently
        require(success, "Callback failed");

        emit RequestFulfilled(requestId, response, err);
    }

    /**
     * @notice Get information about a request
     * @param requestId The request ID
     * @return isFulfilled Whether the request has been fulfilled
     * @return response The response (if fulfilled)
     * @return err Any error (if fulfilled)
     */
    function getRequest(bytes32 requestId)
        external
        view
        returns (bool isFulfilled, bytes memory response, bytes memory err)
    {
        Request storage request = s_requests[requestId];
        require(request.requester != address(0), "Request not found");

        return (request.fulfilled, request.response, request.error);
    }

    /**
     * @notice Get all request IDs
     * @return The array of all request IDs
     */
    function getAllRequestIds() external view returns (bytes32[] memory) {
        return s_requestIds;
    }

    /**
     * @notice Get the latest request ID
     * @return The latest request ID
     */
    function getLatestRequestId() external view returns (bytes32) {
        require(s_requestIds.length > 0, "No requests made");
        return s_requestIds[s_requestIds.length - 1];
    }
}
