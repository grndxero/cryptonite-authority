pragma solidity ^0.4.25;

import "https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.4.25.sol";

interface AcmeProtocol {
    function requestEnrollment(string cName, uint32 csr) external;
    function confirmChallenge(string cName) external;
    function isResolved(string cName) external;
    function signCSR(string cName) external;
}

contract RandomNumberGenerator is usingProvable {
    address public acmeAddr;
    
    constructor() {
        acmeAddr = msg.sender;
    }
    
    function generate() public {
        provable_newRandomDSQuery(0, 32, 200000);
    }
    
    function __callback(bytes32 _queryId, string _result) public {
        uint256 ceiling = (2**256) - 1;
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(_result))) % ceiling;
        
        acmeAddr.call(abi.encodeWithSignature("updateQueue(uint256)", randomNumber));
    }
    
}

contract AcmeClient is usingProvable {
    uint256 public finalResult;
    uint256 public currentQueueValue; 
    uint256 public finalisedCounter; 
    uint256 public testChallengeRequest;
    uint256 public testRandomvalue;
    string public testFinalCNAME;
    uint256 public expectedResult;
    bytes32 public testQID;
    bytes32 public finalQID;

    mapping(uint256 => string) csrQueue; // maps queue value => cName
    mapping(uint256 => string) finalizedCSRs; // maps counter => cName
    mapping(string => uint256) httpChallenge; // maps  cName => httpChallenge
    mapping(string => uint256) csrStore; // maps cName => csr dummy provable_query
    mapping(bytes32 => string) awaitingChallenge; // maps queryID => cName
    RandomNumberGenerator rng;
    
    constructor() public {
        rng = new RandomNumberGenerator();
    }
    
    modifier isRandomNumberGenerator {
        require(msg.sender == address(rng));
        _;
    }
    
    function requestEnrollment(string cName, uint32 csr) public {
        // Associate CSR to a hostname
        csrStore[cName] = csr;
        
        // Add to csrQueue
        csrQueue[currentQueueValue]=cName;
        
        // Generate Random Challenge
        rng.generate();
    }
    
    function getChallengeRequest(string cName) public returns(uint256){
        uint256 challengeString = httpChallenge[cName];
        
        if (challengeString == 0) {
            revert("Challenge not ready");
        } else {
            testChallengeRequest = challengeString;
            return challengeString;
        }
    }
    
    function confirmChallenge(string cName) public {
        string memory siteProtocol = "json(http://";
        string memory challengeParameter = ").challengeResponse";
        string memory url = string(abi.encodePacked(siteProtocol,cName,challengeParameter));
        bytes32 qID = provable_query("URL", url, 200000);
        
        awaitingChallenge[qID] = cName;
        testQID = qID;
    }
    
    function updateQueue(uint256 randomNumber) public isRandomNumberGenerator {
           
        // check queue and provide random string to next request
        string cName = csrQueue[currentQueueValue];
        httpChallenge[cName] = randomNumber;
        currentQueueValue++;
    }
    
    function __callback(bytes32 _queryId, string _result) public {
        // if (msg.sender != oraclizeLib.oraclize_cbAddress()) revert("invalid __callback address")
        finalQID = _queryId;
        string expectedCNAME = awaitingChallenge[_queryId];
        
        // if(expectedCNAME == 0) revert("CNAME DOESN'T MATCH QUERY ID");
        
        expectedResult = httpChallenge[expectedCNAME];
        finalResult = stringToUint(_result);
        
        if(expectedResult == finalResult) {
            finalizedCSRs[finalisedCounter] = expectedCNAME;
        }
    }
    
    function stringToUint(string s) constant returns (uint) {
        bytes memory b = bytes(s);
        uint i;
        uint256 result = 0;
        for (i = 0; i < b.length; i++) {
            uint c = uint(b[i]);
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        
        return result;
    }
    
    function signNextCSR() public returns(string, uint256) {
        string cname = finalizedCSRs[finalisedCounter];
        uint256 csr = csrStore[cname];
        
        testFinalCNAME = cname;
        
        return (cname, csr);
    }
    
}