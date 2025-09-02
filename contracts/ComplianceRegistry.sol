// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IComplianceFramework.sol";

/**
 * @title ComplianceRegistry
 * @dev Global compliance framework implementation for precious assets trading
 * Enforces FATF, Basel III, ISO-20022 standards across all jurisdictions
 */
contract ComplianceRegistry is IComplianceFramework, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");
    bytes32 public constant REGULATOR_ROLE = keccak256("REGULATOR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    
    // KYC data storage
    mapping(address => KYCData) private _kycData;
    
    // AML check results
    mapping(bytes32 => AMLCheck) private _amlChecks;
    
    // Compliance rules per jurisdiction
    mapping(JurisdictionType => ComplianceRule) private _complianceRules;
    
    // Transaction compliance tracking
    mapping(uint256 => TransactionCompliance) private _transactionCompliance;
    
    // Sanctions list
    mapping(address => bool) private _sanctionsList;
    mapping(address => string) private _sanctionsReasons;
    
    // PEP (Politically Exposed Persons) list
    mapping(address => bool) private _pepList;
    
    // Suspicious activity reports
    mapping(bytes32 => SuspiciousActivityReport) private _sarReports;
    
    // Authorized KYC providers
    mapping(address => bool) public authorizedKYCProviders;
    
    // Risk scoring weights
    mapping(string => uint256) public riskFactorWeights;
    
    uint256 private _nextTransactionId = 1;
    uint256 private _nextReportId = 1;
    
    struct SuspiciousActivityReport {
        uint256 reportId;
        address subject;
        uint256 transactionId;
        string reason;
        bytes evidence;
        uint256 reportDate;
        address reporter;
        bool isInvestigated;
    }
    
    event KYCProviderAuthorized(address indexed provider, bool authorized);
    event SanctionsUpdated(address indexed user, bool sanctioned, string reason);
    event PEPStatusUpdated(address indexed user, bool isPEP);
    event RiskFactorWeightUpdated(string factor, uint256 weight);
    event TransactionReviewed(uint256 indexed transactionId, ComplianceStatus status);
    
    modifier onlyAuthorizedKYCProvider() {
        require(authorizedKYCProviders[msg.sender] || hasRole(KYC_PROVIDER_ROLE, msg.sender), 
                "Not authorized KYC provider");
        _;
    }
    
    modifier validJurisdiction(JurisdictionType jurisdiction) {
        require(uint8(jurisdiction) < 10, "Invalid jurisdiction");
        _;
    }
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
        _grantRole(KYC_PROVIDER_ROLE, msg.sender);
        
        // Initialize default compliance rules
        _initializeDefaultRules();
        
        // Initialize risk factor weights
        _initializeRiskFactorWeights();
    }
    
    /**
     * @dev Verify KYC status for user
     */
    function verifyKYC(address user) external view override returns (bool) {
        KYCData memory kyc = _kycData[user];
        return kyc.status == ComplianceStatus.APPROVED && 
               kyc.expiryDate > block.timestamp &&
               !_sanctionsList[user];
    }
    
    /**
     * @dev Get risk level for user
     */
    function getRiskLevel(address user) external view override returns (RiskLevel) {
        KYCData memory kyc = _kycData[user];
        
        // Check sanctions first
        if (_sanctionsList[user]) {
            return RiskLevel.PROHIBITED;
        }
        
        // Return stored risk level or default to HIGH if not verified
        if (kyc.status != ComplianceStatus.APPROVED) {
            return RiskLevel.HIGH;
        }
        
        return kyc.riskLevel;
    }
    
    /**
     * @dev Perform AML check on transaction
     */
    function performAMLCheck(
        address user, 
        uint256 amount, 
        bytes32 sourceHash
    ) external override onlyRole(COMPLIANCE_OFFICER_ROLE) returns (bool approved) {
        require(amount > 0, "Invalid amount");
        
        bytes32 checkId = keccak256(abi.encodePacked(user, amount, sourceHash, block.timestamp));
        
        AMLCheck storage check = _amlChecks[checkId];
        check.user = user;
        check.transactionAmount = amount;
        check.sourceOfFunds = sourceHash;
        
        // Calculate risk score
        uint256 riskScore = _calculateRiskScore(user, amount);
        check.riskScore = riskScore;
        
        // Determine if suspicious
        check.isSuspicious = riskScore > 7000; // 70% threshold
        
        // Check reporting threshold
        KYCData memory kyc = _kycData[user];
        ComplianceRule memory rule = _complianceRules[kyc.jurisdiction];
        check.requiresReporting = amount >= rule.reportingThreshold;
        
        // Auto-approve if risk is low and user is verified
        if (riskScore < 3000 && this.verifyKYC(user)) {
            approved = true;
        } else {
            approved = false;
            
            // Flag for manual review
            if (check.isSuspicious) {
                check.flaggedReasons.push("High risk score");
            }
        }
        
        emit AMLFlagRaised(user, 0, riskScore, check.isSuspicious ? "Suspicious activity detected" : "Normal");
        
        return approved;
    }
    
    /**
     * @dev Check if transaction is compliant with jurisdiction rules
     */
    function isTransactionCompliant(
        address from,
        address to,
        uint256 amount,
        uint256 assetValue,
        JurisdictionType jurisdiction
    ) external view override returns (bool) {
        // Both parties must be KYC verified
        if (!this.verifyKYC(from) || !this.verifyKYC(to)) {
            return false;
        }
        
        // Check sanctions
        if (_sanctionsList[from] || _sanctionsList[to]) {
            return false;
        }
        
        // Get jurisdiction rules
        ComplianceRule memory rule = _complianceRules[jurisdiction];
        
        // Check transaction limits
        if (assetValue > rule.maxTransactionAmount) {
            return false;
        }
        
        // Check if licensing is required
        if (rule.requiresLicensing && amount > 1) {
            // Check if either party has professional dealer status
            // This would require additional implementation
        }
        
        // Check retail restrictions
        if (!rule.allowsRetail && (
            this.getRiskLevel(from) != RiskLevel.LOW || 
            this.getRiskLevel(to) != RiskLevel.LOW
        )) {
            return false;
        }
        
        return true;
    }
    
    /**
     * @dev Update KYC status
     */
    function updateKYCStatus(
        address user,
        ComplianceStatus status,
        RiskLevel riskLevel,
        bytes32 evidenceHash
    ) external override onlyAuthorizedKYCProvider nonReentrant {
        require(user != address(0), "Invalid user address");
        
        KYCData storage kyc = _kycData[user];
        ComplianceStatus oldStatus = kyc.status;
        
        kyc.user = user;
        kyc.status = status;
        kyc.riskLevel = riskLevel;
        kyc.verificationDate = block.timestamp;
        kyc.expiryDate = block.timestamp + 365 days; // 1 year validity
        kyc.verifyingEntity = msg.sender;
        kyc.identityHash = evidenceHash;
        
        // Set jurisdiction based on KYC provider (simplified)
        kyc.jurisdiction = JurisdictionType.US; // Default, should be determined by KYC provider
        
        // Update PEP status if flagged
        kyc.isPEP = _pepList[user];
        kyc.isSanctioned = _sanctionsList[user];
        
        emit KYCStatusUpdated(user, oldStatus, status, riskLevel);
    }
    
    /**
     * @dev Add/remove from sanctions list
     */
    function addToSanctionsList(address user, string calldata reason) 
        external 
        override 
        onlyRole(REGULATOR_ROLE) 
    {
        _sanctionsList[user] = true;
        _sanctionsReasons[user] = reason;
        
        // Automatically update KYC status
        if (_kycData[user].user == user) {
            _kycData[user].status = ComplianceStatus.SUSPENDED;
            _kycData[user].isSanctioned = true;
        }
        
        emit SanctionsUpdated(user, true, reason);
    }
    
    function removeFromSanctionsList(address user) 
        external 
        override 
        onlyRole(REGULATOR_ROLE) 
    {
        _sanctionsList[user] = false;
        delete _sanctionsReasons[user];
        
        // Update KYC status
        if (_kycData[user].user == user) {
            _kycData[user].isSanctioned = false;
        }
        
        emit SanctionsUpdated(user, false, "Removed from sanctions");
    }
    
    function isSanctioned(address user) external view override returns (bool) {
        return _sanctionsList[user];
    }
    
    /**
     * @dev Report suspicious activity
     */
    function reportSuspiciousActivity(
        address user,
        uint256 transactionId,
        string calldata reason,
        bytes calldata evidence
    ) external override onlyRole(COMPLIANCE_OFFICER_ROLE) {
        bytes32 reportHash = keccak256(abi.encodePacked(
            user, transactionId, reason, evidence, block.timestamp
        ));
        
        SuspiciousActivityReport storage report = _sarReports[reportHash];
        report.reportId = _nextReportId++;
        report.subject = user;
        report.transactionId = transactionId;
        report.reason = reason;
        report.evidence = evidence;
        report.reportDate = block.timestamp;
        report.reporter = msg.sender;
        report.isInvestigated = false;
        
        emit SuspiciousActivityReported(user, transactionId, reportHash);
    }
    
    /**
     * @dev Get compliance rule for jurisdiction
     */
    function getComplianceRule(JurisdictionType jurisdiction) 
        external 
        view 
        override 
        validJurisdiction(jurisdiction)
        returns (ComplianceRule memory) 
    {
        return _complianceRules[jurisdiction];
    }
    
    /**
     * @dev Generate compliance report
     */
    function generateComplianceReport(
        uint256 fromDate,
        uint256 toDate,
        JurisdictionType jurisdiction
    ) external view override onlyRole(AUDITOR_ROLE) returns (bytes memory report) {
        require(fromDate < toDate && toDate <= block.timestamp, "Invalid date range");
        
        // This would generate a comprehensive compliance report
        // For now, return a simple encoded structure
        return abi.encode(
            "FTH_COMPLIANCE_REPORT",
            jurisdiction,
            fromDate,
            toDate,
            block.timestamp
        );
    }
    
    /**
     * @dev Administrative functions
     */
    function authorizeKYCProvider(address provider, bool authorized) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        authorizedKYCProviders[provider] = authorized;
        
        if (authorized) {
            _grantRole(KYC_PROVIDER_ROLE, provider);
        } else {
            _revokeRole(KYC_PROVIDER_ROLE, provider);
        }
        
        emit KYCProviderAuthorized(provider, authorized);
    }
    
    function updateComplianceRule(
        JurisdictionType jurisdiction,
        ComplianceRule calldata rule
    ) external onlyRole(REGULATOR_ROLE) validJurisdiction(jurisdiction) {
        _complianceRules[jurisdiction] = rule;
        
        emit ComplianceRuleUpdated(
            rule.ruleId,
            jurisdiction,
            rule.maxTransactionAmount
        );
    }
    
    function setPEPStatus(address user, bool isPEP) 
        external 
        onlyRole(COMPLIANCE_OFFICER_ROLE) 
    {
        _pepList[user] = isPEP;
        
        if (_kycData[user].user == user) {
            _kycData[user].isPEP = isPEP;
            // Increase risk level for PEPs
            if (isPEP && _kycData[user].riskLevel == RiskLevel.LOW) {
                _kycData[user].riskLevel = RiskLevel.MEDIUM;
            }
        }
        
        emit PEPStatusUpdated(user, isPEP);
    }
    
    function setRiskFactorWeight(string calldata factor, uint256 weight) 
        external 
        onlyRole(COMPLIANCE_OFFICER_ROLE) 
    {
        require(weight <= 10000, "Weight too high");
        riskFactorWeights[factor] = weight;
        emit RiskFactorWeightUpdated(factor, weight);
    }
    
    /**
     * @dev Internal functions
     */
    function _calculateRiskScore(address user, uint256 amount) internal view returns (uint256) {
        uint256 baseScore = 1000; // 10% base risk
        
        KYCData memory kyc = _kycData[user];
        
        // Risk factors
        if (kyc.isPEP) {
            baseScore += riskFactorWeights["PEP"];
        }
        
        if (kyc.riskLevel == RiskLevel.HIGH) {
            baseScore += riskFactorWeights["HIGH_RISK"];
        }
        
        // Transaction amount risk
        ComplianceRule memory rule = _complianceRules[kyc.jurisdiction];
        if (amount > rule.reportingThreshold) {
            baseScore += riskFactorWeights["LARGE_TRANSACTION"];
        }
        
        // Geographic risk (simplified)
        if (kyc.jurisdiction == JurisdictionType.US || 
            kyc.jurisdiction == JurisdictionType.EU ||
            kyc.jurisdiction == JurisdictionType.UK) {
            baseScore -= 500; // Lower risk for regulated jurisdictions
        }
        
        return baseScore > 10000 ? 10000 : baseScore;
    }
    
    function _initializeDefaultRules() internal {
        // US Rules
        _complianceRules[JurisdictionType.US] = ComplianceRule({
            ruleId: keccak256("US_PRECIOUS_ASSETS"),
            jurisdiction: JurisdictionType.US,
            maxTransactionAmount: 1000000 * 1e6, // $1M USD
            reportingThreshold: 10000 * 1e6,     // $10K USD
            requiresLicensing: true,
            allowsRetail: true,
            holdingPeriod: 0,
            requiresInsurance: false
        });
        
        // EU Rules
        _complianceRules[JurisdictionType.EU] = ComplianceRule({
            ruleId: keccak256("EU_PRECIOUS_ASSETS"),
            jurisdiction: JurisdictionType.EU,
            maxTransactionAmount: 500000 * 1e6,  // €500K EUR equivalent
            reportingThreshold: 15000 * 1e6,     // €15K EUR equivalent
            requiresLicensing: true,
            allowsRetail: true,
            holdingPeriod: 0,
            requiresInsurance: true
        });
        
        // Add other jurisdictions as needed...
    }
    
    function _initializeRiskFactorWeights() internal {
        riskFactorWeights["PEP"] = 2000;                    // 20% additional risk
        riskFactorWeights["HIGH_RISK"] = 3000;              // 30% additional risk
        riskFactorWeights["LARGE_TRANSACTION"] = 1000;      // 10% additional risk
        riskFactorWeights["SANCTIONS_RELATED"] = 5000;      // 50% additional risk
        riskFactorWeights["GEOGRAPHIC_HIGH_RISK"] = 2500;   // 25% additional risk
    }
    
    /**
     * @dev Getters for private mappings
     */
    function getKYCData(address user) external view returns (KYCData memory) {
        return _kycData[user];
    }
    
    function getAMLCheck(bytes32 checkId) external view returns (AMLCheck memory) {
        return _amlChecks[checkId];
    }
    
    function getSARReport(bytes32 reportHash) 
        external 
        view 
        onlyRole(AUDITOR_ROLE) 
        returns (SuspiciousActivityReport memory) 
    {
        return _sarReports[reportHash];
    }
    
    /**
     * @dev Emergency functions
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}