// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CarbonLedger
 * @dev A decentralized carbon credit tracking and trading system
 * @author CarbonLedger Team
 */
contract CarbonLedger {
    
    // Struct to represent a carbon credit
    struct CarbonCredit {
        uint256 id;
        address issuer;
        address currentOwner;
        uint256 amount; // in tons of CO2 equivalent
        string projectName;
        string location;
        uint256 issuedDate;
        bool isRetired;
        string metadataURI; // IPFS link for additional project data
    }
    
    // State variables
    mapping(uint256 => CarbonCredit) public carbonCredits;
    mapping(address => uint256[]) public ownerCredits;
    mapping(address => bool) public authorizedIssuers;
    mapping(address => uint256) public retiredCredits; // Total retired credits per address
    
    uint256 public nextCreditId;
    address public admin;
    uint256 public totalCreditsIssued;
    uint256 public totalCreditsRetired;
    
    // Events
    event CarbonCreditIssued(
        uint256 indexed creditId,
        address indexed issuer,
        uint256 amount,
        string projectName
    );
    
    event CarbonCreditTransferred(
        uint256 indexed creditId,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    
    event CarbonCreditRetired(
        uint256 indexed creditId,
        address indexed owner,
        uint256 amount,
        string reason
    );
    
    event IssuerAuthorized(address indexed issuer);
    event IssuerRevoked(address indexed issuer);
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }
    
    modifier onlyAuthorizedIssuer() {
        require(authorizedIssuers[msg.sender], "Not an authorized issuer");
        _;
    }
    
    modifier validCreditId(uint256 _creditId) {
        require(_creditId < nextCreditId, "Invalid credit ID");
        _;
    }
    
    modifier onlyOwner(uint256 _creditId) {
        require(
            carbonCredits[_creditId].currentOwner == msg.sender,
            "Not the owner of this credit"
        );
        _;
    }
    
    // Constructor
    constructor() {
        admin = msg.sender;
        nextCreditId = 1;
        authorizedIssuers[msg.sender] = true; // Admin is automatically an authorized issuer
    }
    
    /**
     * @dev Core Function 1: Issue new carbon credits
     * @param _amount Amount of carbon credits in tons of CO2 equivalent
     * @param _projectName Name of the carbon offset project
     * @param _location Geographic location of the project
     * @param _metadataURI IPFS URI containing additional project metadata
     */
    function issueCarbonCredit(
        uint256 _amount,
        string memory _projectName,
        string memory _location,
        string memory _metadataURI
    ) external onlyAuthorizedIssuer returns (uint256) {
        require(_amount > 0, "Amount must be greater than zero");
        require(bytes(_projectName).length > 0, "Project name cannot be empty");
        
        uint256 creditId = nextCreditId;
        
        carbonCredits[creditId] = CarbonCredit({
            id: creditId,
            issuer: msg.sender,
            currentOwner: msg.sender,
            amount: _amount,
            projectName: _projectName,
            location: _location,
            issuedDate: block.timestamp,
            isRetired: false,
            metadataURI: _metadataURI
        });
        
        ownerCredits[msg.sender].push(creditId);
        nextCreditId++;
        totalCreditsIssued += _amount;
        
        emit CarbonCreditIssued(creditId, msg.sender, _amount, _projectName);
        
        return creditId;
    }
    
    /**
     * @dev Core Function 2: Transfer carbon credits between addresses
     * @param _creditId ID of the carbon credit to transfer
     * @param _to Address to transfer the credit to
     * @param _amount Amount of credits to transfer (for partial transfers)
     */
    function transferCarbonCredit(
        uint256 _creditId,
        address _to,
        uint256 _amount
    ) external validCreditId(_creditId) onlyOwner(_creditId) {
        require(_to != address(0), "Cannot transfer to zero address");
        require(_to != msg.sender, "Cannot transfer to yourself");
        require(!carbonCredits[_creditId].isRetired, "Cannot transfer retired credits");
        require(_amount > 0 && _amount <= carbonCredits[_creditId].amount, "Invalid amount");
        
        CarbonCredit storage credit = carbonCredits[_creditId];
        
        if (_amount == credit.amount) {
            // Full transfer
            credit.currentOwner = _to;
            
            // Update owner mappings
            _removeFromOwnerCredits(msg.sender, _creditId);
            ownerCredits[_to].push(_creditId);
        } else {
            // Partial transfer - create new credit for the transferred amount
            uint256 newCreditId = nextCreditId;
            
            carbonCredits[newCreditId] = CarbonCredit({
                id: newCreditId,
                issuer: credit.issuer,
                currentOwner: _to,
                amount: _amount,
                projectName: credit.projectName,
                location: credit.location,
                issuedDate: credit.issuedDate,
                isRetired: false,
                metadataURI: credit.metadataURI
            });
            
            // Update original credit amount
            credit.amount -= _amount;
            
            ownerCredits[_to].push(newCreditId);
            nextCreditId++;
        }
        
        emit CarbonCreditTransferred(_creditId, msg.sender, _to, _amount);
    }
    
    /**
     * @dev Core Function 3: Retire carbon credits (permanent removal from circulation)
     * @param _creditId ID of the carbon credit to retire
     * @param _amount Amount of credits to retire
     * @param _reason Reason for retirement (e.g., "Corporate offset for 2024")
     */
    function retireCarbonCredit(
        uint256 _creditId,
        uint256 _amount,
        string memory _reason
    ) external validCreditId(_creditId) onlyOwner(_creditId) {
        require(!carbonCredits[_creditId].isRetired, "Credit already retired");
        require(_amount > 0 && _amount <= carbonCredits[_creditId].amount, "Invalid amount");
        require(bytes(_reason).length > 0, "Retirement reason required");
        
        CarbonCredit storage credit = carbonCredits[_creditId];
        
        if (_amount == credit.amount) {
            // Full retirement
            credit.isRetired = true;
        } else {
            // Partial retirement - reduce the amount
            credit.amount -= _amount;
        }
        
        retiredCredits[msg.sender] += _amount;
        totalCreditsRetired += _amount;
        
        emit CarbonCreditRetired(_creditId, msg.sender, _amount, _reason);
    }
    
    // Admin functions
    function authorizeIssuer(address _issuer) external onlyAdmin {
        require(_issuer != address(0), "Invalid issuer address");
        authorizedIssuers[_issuer] = true;
        emit IssuerAuthorized(_issuer);
    }
    
    function revokeIssuer(address _issuer) external onlyAdmin {
        require(_issuer != admin, "Cannot revoke admin");
        authorizedIssuers[_issuer] = false;
        emit IssuerRevoked(_issuer);
    }
    
    // View functions
    function getCarbonCredit(uint256 _creditId) external view validCreditId(_creditId) 
        returns (CarbonCredit memory) {
        return carbonCredits[_creditId];
    }
    
    function getOwnerCredits(address _owner) external view returns (uint256[] memory) {
        return ownerCredits[_owner];
    }
    
    function getTotalRetiredByAddress(address _owner) external view returns (uint256) {
        return retiredCredits[_owner];
    }
    
    function getContractStats() external view returns (
        uint256 _totalIssued,
        uint256 _totalRetired,
        uint256 _totalActive,
        uint256 _nextCreditId
    ) {
        return (
            totalCreditsIssued,
            totalCreditsRetired,
            totalCreditsIssued - totalCreditsRetired,
            nextCreditId
        );
    }
    
    // Internal helper function
    function _removeFromOwnerCredits(address _owner, uint256 _creditId) internal {
        uint256[] storage credits = ownerCredits[_owner];
        for (uint256 i = 0; i < credits.length; i++) {
            if (credits[i] == _creditId) {
                credits[i] = credits[credits.length - 1];
                credits.pop();
                break;
            }
        }
    }
}
