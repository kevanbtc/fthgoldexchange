// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IComplianceFramework - Global Regulatory Compliance
 * @dev Enforces FATF, Basel III, ISO-20022, and jurisdiction-specific rules
 */
interface IComplianceFramework {
    
    enum ComplianceStatus {
        PENDING,
        APPROVED, 
        REJECTED,
        SUSPENDED,
        EXPIRED
    }
    
    enum RiskLevel {
        LOW,
        MEDIUM,
        HIGH,
        PROHIBITED
    }
    
    enum JurisdictionType {
        US,             // United States
        EU,             // European Union
        UK,             // United Kingdom
        SINGAPORE,      // Singapore
        SWITZERLAND,    // Switzerland
        DUBAI,          // UAE/DMCC
        HONGKONG,       // Hong Kong
        CANADA,         // Canada
        AUSTRALIA,      // Australia
        JAPAN          // Japan
    }
    
    struct KYCData {
        address user;
        bytes32 identityHash;       // Hash of identity documents
        uint256 verificationDate;
        uint256 expiryDate;
        ComplianceStatus status;
        RiskLevel riskLevel;
        JurisdictionType jurisdiction;
        bool isPEP;                 // Politically Exposed Person
        bool isSanctioned;          // On sanctions list
        address verifyingEntity;    // KYC provider
    }
    
    struct AMLCheck {
        address user;
        uint256 transactionAmount;
        bytes32 sourceOfFunds;      // Hash of source documentation
        bool requiresReporting;     // Above reporting threshold
        bool isSuspicious;          // Suspicious activity flag
        uint256 riskScore;          // 0-100 risk score
        string[] flaggedReasons;    // Array of risk factors
    }
    
    struct ComplianceRule {
        bytes32 ruleId;
        JurisdictionType jurisdiction;
        uint256 maxTransactionAmount;   // Without additional checks
        uint256 reportingThreshold;     // Mandatory reporting above
        bool requiresLicensing;         // Professional dealer license
        bool allowsRetail;              // Retail investor access
        uint256 holdingPeriod;          // Minimum holding period
        bool requiresInsurance;         // Mandatory insurance
    }
    
    struct TransactionCompliance {
        uint256 transactionId;
        address from;
        address to;
        uint256 amount;
        uint256 assetValue;
        ComplianceStatus status;
        bytes32[] requiredDocuments;    // Required compliance docs
        bytes32[] submittedDocuments;   // Submitted compliance docs
        uint256 reviewDeadline;
        address complianceOfficer;
    }
    
    event KYCStatusUpdated(
        address indexed user,
        ComplianceStatus oldStatus,
        ComplianceStatus newStatus,
        RiskLevel riskLevel
    );
    
    event AMLFlagRaised(
        address indexed user,
        uint256 indexed transactionId,
        uint256 riskScore,
        string reason
    );
    
    event ComplianceRuleUpdated(
        bytes32 indexed ruleId,
        JurisdictionType jurisdiction,
        uint256 maxAmount
    );
    
    event SuspiciousActivityReported(
        address indexed user,
        uint256 indexed transactionId,
        bytes32 reportHash
    );
    
    function verifyKYC(address user) external view returns (bool);
    
    function getRiskLevel(address user) external view returns (RiskLevel);
    
    function performAMLCheck(
        address user, 
        uint256 amount, 
        bytes32 sourceHash
    ) external returns (bool approved);
    
    function isTransactionCompliant(
        address from,
        address to,
        uint256 amount,
        uint256 assetValue,
        JurisdictionType jurisdiction
    ) external view returns (bool);
    
    function getComplianceRule(JurisdictionType jurisdiction) 
        external 
        view 
        returns (ComplianceRule memory);
    
    function reportSuspiciousActivity(
        address user,
        uint256 transactionId,
        string calldata reason,
        bytes calldata evidence
    ) external;
    
    function updateKYCStatus(
        address user,
        ComplianceStatus status,
        RiskLevel riskLevel,
        bytes32 evidenceHash
    ) external;
    
    function addToSanctionsList(address user, string calldata reason) external;
    
    function removeFromSanctionsList(address user) external;
    
    function isSanctioned(address user) external view returns (bool);
    
    function generateComplianceReport(
        uint256 fromDate,
        uint256 toDate,
        JurisdictionType jurisdiction
    ) external view returns (bytes memory report);
}