// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./ComplianceRegistry.sol";

/**
 * @title GoldTransactionFramework
 * @notice Standardized legal + financial framework for all Future Tech Holdings (FTH/Unykorn) gold transactions
 * @dev This contract establishes binding structures for SPVs, partnerships, and infrastructure agreements
 *      with on-chain audit trails, compliance checks, and escrow settlement logic.
 * @author Future Tech Holdings
 */
contract GoldTransactionFramework is AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant LEGAL_OFFICER_ROLE = keccak256("LEGAL_OFFICER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    // --- Events ---
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed counterparty,
        AgreementType agreementType,
        string jurisdiction,
        bytes32 legalDocumentHash
    );
    
    event AssetRegistered(
        uint256 indexed agreementId, 
        string indexed assetId, 
        uint256 weightInGrams,
        bytes32 certificationHash
    );
    
    event EscrowFunded(
        uint256 indexed agreementId, 
        uint256 amount, 
        address indexed funder,
        string fundingReason
    );
    
    event EscrowReleased(
        uint256 indexed agreementId, 
        uint256 amount, 
        address indexed recipient,
        string releaseReason
    );
    
    event ComplianceReview(
        uint256 indexed agreementId, 
        bool passed, 
        string reason,
        address indexed reviewer
    );
    
    event MilestoneCompleted(
        uint256 indexed agreementId,
        uint8 milestoneIndex,
        uint256 paymentAmount,
        bytes32 evidenceHash
    );
    
    event DisputeRaised(
        uint256 indexed agreementId,
        address indexed initiator,
        string reason,
        uint256 disputeDeadline
    );
    
    event LegalTemplateUpdated(
        AgreementType agreementType,
        string jurisdiction,
        bytes32 templateHash,
        uint256 version
    );

    // --- Enum Types ---
    enum AgreementType { 
        SPV,                    // Special Purpose Vehicle
        PARTNERSHIP,            // Strategic partnership
        INFRASTRUCTURE,         // Infrastructure build agreement
        DIRECT_SALE,           // Direct asset purchase
        VAULT_SERVICES,        // Vault operator agreement
        REFINERY_SERVICES,     // Refinery partnership
        LOGISTICS_SERVICES,    // Transportation/logistics
        INSURANCE_COVERAGE,    // Insurance provider agreement
        COMPLIANCE_SERVICES    // KYC/AML service provider
    }

    enum Status { 
        DRAFT,                 // Being negotiated
        PENDING,              // Awaiting signatures
        ACTIVE,               // Fully executed
        MILESTONE_PENDING,    // Awaiting milestone completion
        DISPUTED,             // Under dispute resolution
        COMPLETED,            // Successfully completed
        TERMINATED,           // Terminated early
        EXPIRED               // Expired without completion
    }

    enum ComplianceLevel {
        BASIC,                // Standard KYC/AML
        ENHANCED,             // Enhanced due diligence
        ULTRA,                // Ultra high net worth
        INSTITUTIONAL,        // Institutional grade
        SOVEREIGN             // Sovereign/government level
    }

    // --- Structs ---
    struct Agreement {
        AgreementType agreementType;
        string jurisdiction;              // e.g., "Delaware", "Mauritius", "Cayman Islands"
        bytes32 legalDocumentHash;       // IPFS hash of signed legal agreement
        address counterparty;            // Vault/refinery/partner wallet address
        string counterpartyLegalName;    // Full legal entity name
        uint256 totalValue;              // Total agreement value in USD (6 decimals)
        uint256 escrowBalance;           // Current locked funds in escrow
        Status status;
        ComplianceLevel complianceRequired;
        uint256 createdAt;
        uint256 expiryDate;              // Agreement expiration
        bool requiresMilestones;         // Whether this agreement uses milestone payments
        uint8 completedMilestones;       // Number of milestones completed
        uint8 totalMilestones;          // Total number of milestones
        address assignedLegalCounsel;    // Assigned legal representative
        string externalAgreementId;      // Reference to external legal system
    }

    struct AssetRegistration {
        string assetId;                  // UAID identifier
        uint256 weightInGrams;          // Asset weight
        uint256 valueUSD;               // Asset value in USD
        bytes32 certificationHash;      // Certification document hash
        string certifyingAuthority;     // Who certified the asset
        uint256 registrationDate;       // When asset was registered
        bool isActive;                  // Whether asset is still under this agreement
    }

    struct Milestone {
        string description;              // What needs to be delivered
        uint256 paymentAmount;          // Payment for this milestone
        bytes32 requirementHash;        // IPFS hash of detailed requirements
        bool isCompleted;               // Completion status
        uint256 completionDate;         // When milestone was completed
        bytes32 evidenceHash;           // IPFS hash of completion evidence
        address approvedBy;             // Who approved completion
    }

    struct LegalTemplate {
        bytes32 templateHash;           // IPFS hash of legal template
        uint256 version;                // Template version number
        string jurisdiction;            // Applicable jurisdiction
        bool isActive;                  // Whether template is current
        uint256 lastUpdated;           // Last update timestamp
        address updatedBy;             // Who updated the template
    }

    struct DisputeInfo {
        address initiator;              // Who raised the dispute
        string reason;                  // Dispute description
        uint256 raisedDate;            // When dispute was raised
        uint256 resolutionDeadline;    // Deadline for resolution
        bool isResolved;               // Resolution status
        string resolution;             // Resolution details
        address resolvedBy;            // Who resolved the dispute
    }

    // --- Storage ---
    uint256 public agreementCounter;
    mapping(uint256 => Agreement) public agreements;
    
    // Asset registrations per agreement
    mapping(uint256 => AssetRegistration[]) public agreementAssets;
    
    // Milestones per agreement
    mapping(uint256 => Milestone[]) public agreementMilestones;
    
    // Legal templates by type and jurisdiction
    mapping(AgreementType => mapping(string => LegalTemplate)) public legalTemplates;
    
    // Dispute information
    mapping(uint256 => DisputeInfo) public disputes;
    
    // Compliance framework integration
    ComplianceRegistry public complianceRegistry;
    
    // Fee structure
    uint256 public platformFeeBps = 50;        // 0.5% platform fee
    uint256 public escrowFeeBps = 10;          // 0.1% escrow fee
    address public treasuryAddress;            // FTH treasury
    
    // Legal and operational addresses
    address public defaultLegalCounsel;
    address public disputeArbitrator;
    
    modifier onlyCounterparty(uint256 agreementId) {
        require(
            msg.sender == agreements[agreementId].counterparty ||
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized counterparty"
        );
        _;
    }
    
    modifier validAgreement(uint256 agreementId) {
        require(agreementId <= agreementCounter && agreementId > 0, "Invalid agreement ID");
        require(agreements[agreementId].status != Status.EXPIRED, "Agreement expired");
        _;
    }
    
    modifier notDisputed(uint256 agreementId) {
        require(agreements[agreementId].status != Status.DISPUTED, "Agreement under dispute");
        _;
    }

    constructor(
        address _complianceRegistry,
        address _treasuryAddress,
        address _defaultLegalCounsel
    ) {
        require(_complianceRegistry != address(0), "Invalid compliance registry");
        require(_treasuryAddress != address(0), "Invalid treasury address");
        
        complianceRegistry = ComplianceRegistry(_complianceRegistry);
        treasuryAddress = _treasuryAddress;
        defaultLegalCounsel = _defaultLegalCounsel;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
        _grantRole(LEGAL_OFFICER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, _treasuryAddress);
    }

    // --- Core Agreement Functions ---

    /**
     * @notice Create a new legally binding gold transaction agreement
     * @param _type Type of agreement (SPV, Partnership, etc.)
     * @param _jurisdiction Legal jurisdiction (e.g., "Delaware", "Mauritius")
     * @param _legalDocumentHash IPFS hash of signed legal agreement
     * @param _counterparty Counterparty wallet address
     * @param _counterpartyLegalName Full legal entity name
     * @param _totalValue Total agreement value in USD (6 decimals)
     * @param _expiryDate Agreement expiration timestamp
     * @param _complianceLevel Required compliance level
     */
    function createAgreement(
        AgreementType _type,
        string calldata _jurisdiction,
        bytes32 _legalDocumentHash,
        address _counterparty,
        string calldata _counterpartyLegalName,
        uint256 _totalValue,
        uint256 _expiryDate,
        ComplianceLevel _complianceLevel,
        string calldata _externalAgreementId
    ) external onlyRole(LEGAL_OFFICER_ROLE) whenNotPaused nonReentrant returns (uint256) {
        require(_counterparty != address(0), "Invalid counterparty address");
        require(_totalValue > 0, "Invalid total value");
        require(_expiryDate > block.timestamp, "Invalid expiry date");
        require(bytes(_counterpartyLegalName).length > 0, "Legal name required");
        
        // Verify counterparty compliance
        require(
            complianceRegistry.verifyKYC(_counterparty),
            "Counterparty KYC verification required"
        );
        
        // Verify legal template exists
        require(
            legalTemplates[_type][_jurisdiction].isActive,
            "No active legal template for this type and jurisdiction"
        );
        
        agreementCounter++;
        
        agreements[agreementCounter] = Agreement({
            agreementType: _type,
            jurisdiction: _jurisdiction,
            legalDocumentHash: _legalDocumentHash,
            counterparty: _counterparty,
            counterpartyLegalName: _counterpartyLegalName,
            totalValue: _totalValue,
            escrowBalance: 0,
            status: Status.DRAFT,
            complianceRequired: _complianceLevel,
            createdAt: block.timestamp,
            expiryDate: _expiryDate,
            requiresMilestones: false,
            completedMilestones: 0,
            totalMilestones: 0,
            assignedLegalCounsel: defaultLegalCounsel,
            externalAgreementId: _externalAgreementId
        });

        emit AgreementCreated(
            agreementCounter,
            _counterparty,
            _type,
            _jurisdiction,
            _legalDocumentHash
        );

        return agreementCounter;
    }

    /**
     * @notice Register a gold asset under an agreement with UAID
     * @param _agreementId Agreement ID
     * @param _assetId UAID identifier
     * @param _weightInGrams Asset weight in grams
     * @param _valueUSD Asset value in USD (6 decimals)
     * @param _certificationHash Hash of certification documents
     * @param _certifyingAuthority Name of certifying authority
     */
    function registerAsset(
        uint256 _agreementId,
        string calldata _assetId,
        uint256 _weightInGrams,
        uint256 _valueUSD,
        bytes32 _certificationHash,
        string calldata _certifyingAuthority
    ) external onlyRole(LEGAL_OFFICER_ROLE) validAgreement(_agreementId) nonReentrant {
        require(_weightInGrams > 0, "Invalid weight");
        require(_valueUSD > 0, "Invalid value");
        require(bytes(_assetId).length > 0, "Asset ID required");
        require(bytes(_certifyingAuthority).length > 0, "Certifying authority required");
        
        agreementAssets[_agreementId].push(AssetRegistration({
            assetId: _assetId,
            weightInGrams: _weightInGrams,
            valueUSD: _valueUSD,
            certificationHash: _certificationHash,
            certifyingAuthority: _certifyingAuthority,
            registrationDate: block.timestamp,
            isActive: true
        }));
        
        emit AssetRegistered(_agreementId, _assetId, _weightInGrams, _certificationHash);
    }

    /**
     * @notice Set up milestone-based payment structure
     * @param _agreementId Agreement ID
     * @param _descriptions Array of milestone descriptions
     * @param _paymentAmounts Array of payment amounts per milestone
     * @param _requirementHashes Array of IPFS hashes for detailed requirements
     */
    function setupMilestones(
        uint256 _agreementId,
        string[] calldata _descriptions,
        uint256[] calldata _paymentAmounts,
        bytes32[] calldata _requirementHashes
    ) external onlyRole(LEGAL_OFFICER_ROLE) validAgreement(_agreementId) {
        require(_descriptions.length == _paymentAmounts.length, "Array length mismatch");
        require(_descriptions.length == _requirementHashes.length, "Array length mismatch");
        require(_descriptions.length > 0, "No milestones provided");
        
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.status == Status.DRAFT, "Cannot modify active agreement");
        
        // Clear existing milestones
        delete agreementMilestones[_agreementId];
        
        uint256 totalMilestoneValue = 0;
        for (uint256 i = 0; i < _descriptions.length; i++) {
            require(_paymentAmounts[i] > 0, "Invalid payment amount");
            totalMilestoneValue += _paymentAmounts[i];
            
            agreementMilestones[_agreementId].push(Milestone({
                description: _descriptions[i],
                paymentAmount: _paymentAmounts[i],
                requirementHash: _requirementHashes[i],
                isCompleted: false,
                completionDate: 0,
                evidenceHash: bytes32(0),
                approvedBy: address(0)
            }));
        }
        
        require(totalMilestoneValue <= agreement.totalValue, "Milestone total exceeds agreement value");
        
        agreement.requiresMilestones = true;
        agreement.totalMilestones = uint8(_descriptions.length);
    }

    // --- Escrow Functions ---

    /**
     * @notice Fund escrow for an agreement
     * @param _agreementId Agreement ID
     * @param _fundingReason Reason for funding
     */
    function fundEscrow(
        uint256 _agreementId, 
        string calldata _fundingReason
    ) external payable validAgreement(_agreementId) nonReentrant {
        require(msg.value > 0, "No funds provided");
        
        Agreement storage agreement = agreements[_agreementId];
        require(
            msg.sender == agreement.counterparty || 
            hasRole(TREASURY_ROLE, msg.sender),
            "Not authorized to fund"
        );
        
        // Calculate platform fee
        uint256 platformFee = (msg.value * platformFeeBps) / 10000;
        uint256 netAmount = msg.value - platformFee;
        
        agreement.escrowBalance += netAmount;
        
        // Transfer platform fee to treasury
        if (platformFee > 0) {
            payable(treasuryAddress).transfer(platformFee);
        }
        
        emit EscrowFunded(_agreementId, netAmount, msg.sender, _fundingReason);
    }

    /**
     * @notice Release escrow funds after compliance approval
     * @param _agreementId Agreement ID
     * @param _recipient Recipient address
     * @param _amount Amount to release
     * @param _releaseReason Reason for release
     */
    function releaseEscrow(
        uint256 _agreementId,
        address payable _recipient,
        uint256 _amount,
        string calldata _releaseReason
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) validAgreement(_agreementId) nonReentrant {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.status == Status.ACTIVE, "Agreement not active");
        require(agreement.escrowBalance >= _amount, "Insufficient escrow balance");
        require(_recipient != address(0), "Invalid recipient");
        
        agreement.escrowBalance -= _amount;
        
        // Calculate escrow fee
        uint256 escrowFee = (_amount * escrowFeeBps) / 10000;
        uint256 netAmount = _amount - escrowFee;
        
        _recipient.transfer(netAmount);
        
        if (escrowFee > 0) {
            payable(treasuryAddress).transfer(escrowFee);
        }
        
        emit EscrowReleased(_agreementId, netAmount, _recipient, _releaseReason);
    }

    /**
     * @notice Complete a milestone and trigger payment
     * @param _agreementId Agreement ID
     * @param _milestoneIndex Index of milestone to complete
     * @param _evidenceHash IPFS hash of completion evidence
     */
    function completeMilestone(
        uint256 _agreementId,
        uint8 _milestoneIndex,
        bytes32 _evidenceHash
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) validAgreement(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.requiresMilestones, "Agreement doesn't use milestones");
        require(_milestoneIndex < agreement.totalMilestones, "Invalid milestone index");
        
        Milestone storage milestone = agreementMilestones[_agreementId][_milestoneIndex];
        require(!milestone.isCompleted, "Milestone already completed");
        require(agreement.escrowBalance >= milestone.paymentAmount, "Insufficient escrow funds");
        
        milestone.isCompleted = true;
        milestone.completionDate = block.timestamp;
        milestone.evidenceHash = _evidenceHash;
        milestone.approvedBy = msg.sender;
        
        agreement.completedMilestones++;
        agreement.escrowBalance -= milestone.paymentAmount;
        
        // Auto-release payment to counterparty
        uint256 escrowFee = (milestone.paymentAmount * escrowFeeBps) / 10000;
        uint256 netAmount = milestone.paymentAmount - escrowFee;
        
        payable(agreement.counterparty).transfer(netAmount);
        
        if (escrowFee > 0) {
            payable(treasuryAddress).transfer(escrowFee);
        }
        
        // Check if agreement is fully completed
        if (agreement.completedMilestones == agreement.totalMilestones) {
            agreement.status = Status.COMPLETED;
        }
        
        emit MilestoneCompleted(_agreementId, _milestoneIndex, netAmount, _evidenceHash);
    }

    // --- Compliance Functions ---

    /**
     * @notice Perform comprehensive compliance review
     * @param _agreementId Agreement ID
     * @param _passed Whether compliance check passed
     * @param _reason Detailed reason for decision
     */
    function performComplianceReview(
        uint256 _agreementId,
        bool _passed,
        string calldata _reason
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) validAgreement(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.status == Status.PENDING, "Invalid status for compliance review");
        
        // Enhanced compliance checks based on level
        if (_passed) {
            if (agreement.complianceRequired == ComplianceLevel.ENHANCED ||
                agreement.complianceRequired == ComplianceLevel.ULTRA ||
                agreement.complianceRequired == ComplianceLevel.INSTITUTIONAL ||
                agreement.complianceRequired == ComplianceLevel.SOVEREIGN) {
                
                // Perform additional AML check
                require(
                    complianceRegistry.performAMLCheck(
                        agreement.counterparty,
                        agreement.totalValue,
                        agreement.legalDocumentHash
                    ),
                    "Enhanced AML check failed"
                );
            }
            
            agreement.status = Status.ACTIVE;
        } else {
            agreement.status = Status.TERMINATED;
            
            // Refund any escrow funds
            if (agreement.escrowBalance > 0) {
                uint256 refundAmount = agreement.escrowBalance;
                agreement.escrowBalance = 0;
                payable(agreement.counterparty).transfer(refundAmount);
            }
        }
        
        emit ComplianceReview(_agreementId, _passed, _reason, msg.sender);
    }

    // --- Dispute Resolution ---

    /**
     * @notice Raise a dispute for an agreement
     * @param _agreementId Agreement ID
     * @param _reason Dispute reason
     */
    function raiseDispute(
        uint256 _agreementId,
        string calldata _reason
    ) external validAgreement(_agreementId) onlyCounterparty(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.status == Status.ACTIVE, "Can only dispute active agreements");
        require(bytes(_reason).length > 0, "Dispute reason required");
        
        agreement.status = Status.DISPUTED;
        
        disputes[_agreementId] = DisputeInfo({
            initiator: msg.sender,
            reason: _reason,
            raisedDate: block.timestamp,
            resolutionDeadline: block.timestamp + 30 days, // 30 day resolution window
            isResolved: false,
            resolution: "",
            resolvedBy: address(0)
        });
        
        emit DisputeRaised(_agreementId, msg.sender, _reason, disputes[_agreementId].resolutionDeadline);
    }

    /**
     * @notice Resolve a dispute
     * @param _agreementId Agreement ID
     * @param _resolution Resolution details
     * @param _favorBuyer Whether resolution favors buyer
     */
    function resolveDispute(
        uint256 _agreementId,
        string calldata _resolution,
        bool _favorBuyer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) validAgreement(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.status == Status.DISPUTED, "No active dispute");
        
        DisputeInfo storage dispute = disputes[_agreementId];
        require(!dispute.isResolved, "Dispute already resolved");
        
        dispute.isResolved = true;
        dispute.resolution = _resolution;
        dispute.resolvedBy = msg.sender;
        
        if (_favorBuyer) {
            // Refund escrow to buyer (whoever funded it)
            if (agreement.escrowBalance > 0) {
                // Implementation depends on tracking who funded escrow
                // For simplicity, refund to counterparty
                uint256 refundAmount = agreement.escrowBalance;
                agreement.escrowBalance = 0;
                payable(agreement.counterparty).transfer(refundAmount);
            }
            agreement.status = Status.TERMINATED;
        } else {
            // Resume agreement
            agreement.status = Status.ACTIVE;
        }
    }

    // --- Legal Template Management ---

    /**
     * @notice Update legal template for agreement type and jurisdiction
     * @param _type Agreement type
     * @param _jurisdiction Legal jurisdiction
     * @param _templateHash IPFS hash of legal template
     * @param _version Template version
     */
    function updateLegalTemplate(
        AgreementType _type,
        string calldata _jurisdiction,
        bytes32 _templateHash,
        uint256 _version
    ) external onlyRole(LEGAL_OFFICER_ROLE) {
        require(_templateHash != bytes32(0), "Invalid template hash");
        require(_version > 0, "Invalid version");
        
        LegalTemplate storage template = legalTemplates[_type][_jurisdiction];
        
        // Deactivate old version
        if (template.version > 0) {
            template.isActive = false;
        }
        
        // Set new template
        legalTemplates[_type][_jurisdiction] = LegalTemplate({
            templateHash: _templateHash,
            version: _version,
            jurisdiction: _jurisdiction,
            isActive: true,
            lastUpdated: block.timestamp,
            updatedBy: msg.sender
        });
        
        emit LegalTemplateUpdated(_type, _jurisdiction, _templateHash, _version);
    }

    // --- View Functions ---

    /**
     * @notice Get agreement details
     * @param _agreementId Agreement ID
     * @return Agreement struct
     */
    function getAgreement(uint256 _agreementId) external view returns (Agreement memory) {
        return agreements[_agreementId];
    }

    /**
     * @notice Get all assets registered under an agreement
     * @param _agreementId Agreement ID
     * @return Array of AssetRegistration structs
     */
    function getAgreementAssets(uint256 _agreementId) external view returns (AssetRegistration[] memory) {
        return agreementAssets[_agreementId];
    }

    /**
     * @notice Get all milestones for an agreement
     * @param _agreementId Agreement ID
     * @return Array of Milestone structs
     */
    function getAgreementMilestones(uint256 _agreementId) external view returns (Milestone[] memory) {
        return agreementMilestones[_agreementId];
    }

    /**
     * @notice Get dispute information
     * @param _agreementId Agreement ID
     * @return DisputeInfo struct
     */
    function getDispute(uint256 _agreementId) external view returns (DisputeInfo memory) {
        return disputes[_agreementId];
    }

    /**
     * @notice Get legal template for agreement type and jurisdiction
     * @param _type Agreement type
     * @param _jurisdiction Legal jurisdiction
     * @return LegalTemplate struct
     */
    function getLegalTemplate(
        AgreementType _type, 
        string calldata _jurisdiction
    ) external view returns (LegalTemplate memory) {
        return legalTemplates[_type][_jurisdiction];
    }

    // --- Admin Functions ---

    /**
     * @notice Update platform fees
     * @param _platformFeeBps Platform fee in basis points
     * @param _escrowFeeBps Escrow fee in basis points
     */
    function updateFees(
        uint256 _platformFeeBps,
        uint256 _escrowFeeBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_platformFeeBps <= 500, "Platform fee too high"); // Max 5%
        require(_escrowFeeBps <= 100, "Escrow fee too high"); // Max 1%
        
        platformFeeBps = _platformFeeBps;
        escrowFeeBps = _escrowFeeBps;
    }

    /**
     * @notice Update treasury address
     * @param _newTreasury New treasury address
     */
    function updateTreasury(address _newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newTreasury != address(0), "Invalid treasury address");
        treasuryAddress = _newTreasury;
        _grantRole(TREASURY_ROLE, _newTreasury);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Resume operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency fund recovery (only if paused)
     */
    function emergencyRecoverFunds(
        uint256 _agreementId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.escrowBalance > 0, "No funds to recover");
        
        uint256 amount = agreement.escrowBalance;
        agreement.escrowBalance = 0;
        
        payable(treasuryAddress).transfer(amount);
    }

    // --- Fallback ---
    receive() external payable {
        revert("Direct payments not accepted");
    }
}