// SPDX-License-Identifier: GPL-3.0

//smart contract KYC being deployed on the ganache local blockchain, to miantain all functions done by admin bank and other participating banks

//Karam Issa
pragma solidity ^0.6.0;

contract KYC {
    //Admin Account
    address admin;

    //this modifier will be used on functions that only the admin can transact
    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }

    //user-defined data type that restrict the variable to have only one of the predefined values for certain Bank actions
    enum BankActions {
        //requestActions
        AddKYCRequest, //0
        RemoveKYCRequest, //1
        //KYC for a requested customer
        ApproveKYC, //2
        DeclineKYC, //3
        //bank actions on customers
        AddCustomer, //4
        RemoveCustomer, //5
        ModifyCustomer, //6
        ViewCustomer //7
    }

    //user-defined data type that restrict the variable to have only one of the predefined values for certain Kyc Status where pending is the defualt.
    enum KycStatus {
        Pending, //0
        Approved, //1
        Declined //2
    }

    //An event is an inheritable member of the contract, which stores the arguments passed in the transaction logs when emitted.
    event ContractInitialized();
    //kyc events
    event CustomerKYCRequestAdded();
    event CustomerKYCRequestRemoved();
    event CustomerKYCRequestApproved();
    //customer events
    event NewCustomerCreated(uint256 uniqueId);
    event CustomerRemoved();
    event CustomerInfoModified();
    //bank events
    event NewBankCreated();
    event BankRemoved();
    event BankBlockedFromKYC();

    //Struct types are used to represent a record
    //Customer struct will record all customers regardless of their kyc status
    struct Customer {
        string firstName;
        string lastName;
        string data;
        uint256 uniqueId; //derived from national id
        address validatedBank;
        KycStatus status;
    }

    //Bank struct will record all Banks and their information including the admin
    struct Bank {
        string name;
        string regNumber;
        uint256 kycCount; //count of how many requests a specific bank has requested
        address ethAddress;
        bool isAllowedToAddCustomer; //permission to add new customers,only given to a few banks that the super admin trusts with identity validation and verification
        bool kycPrivilege; //permisiion to request/delete new KYC reports on customers and to view the
    }

    //Banks will request the latest KYC status of customers, and this request will be stored in a KYCRequest struct
    struct KYCRequest {
        uint256 customerUniqueId;
        address bankAddress;
        bool adminResponse;
    }

    address[] public bankAddressess; //to keep list of bank addresses, so that we can loop through when required;
    uint256[] public customerUniqueIds; // to keep a list of all customers unique ids so that we can loop through when required

    mapping(uint256 => Customer) public customersInformation; //mapping a customers's uniqueId to CUstomer Struct
    mapping(address => Bank) public banks; //  Mapping a bank's address to the Bank
    mapping(string => Bank) public banksRegestrationNumberMapping;
    mapping(uint256 => KYCRequest) public kycRequests; //mapping a customers id to KYC Request

    mapping(address => mapping(int256 => uint256)) bankActionsAudit; //to track each bank and their actions with time stamp

    //--Public functions can be called from anywhere.
    //--External functions are part of the contract interface, which means they can be called from other contracts and via transactions.

    // The constructor is called when an contract is first created and is used to initialize state variables in a contract.
    constructor() public {
        emit ContractInitialized();

        //admin will store the address of the deployer of the contract
        admin = msg.sender;

        //the banks mapping will be initialized with the super admin bank, with:
        //1.isAllowedToAddCustomer : true
        //2.kycPrivilege : true;
        
        banks[admin] = Bank("AdminBank", "1", 0, admin, true, true);

        //adding teh adminBank address to the bankAddressess array
        bankAddressess.push(admin);

        //initialize the banksRegestrationNumberMapping mapping with the admin regNumber: 1
        banksRegestrationNumberMapping["1"] = banks[admin];
    }

    /*
        * Name: addKYCRequest
        * Description:This function is used to add the kyc request to the requests list.
          If Kyc privilege is set to false, bank won't be allowed to add requests for any customer.
        * Param1: {uint256} custUniqueId_ : the unique id of the customer for whom KYC is to be done.
    */

    function addKYCRequest(uint256 custUniqueId_) public returns (bool) {
        //check that sender of transaction is found in the banks mapping AND and has kycPrivilege True;
        require(
            banks[msg.sender].kycPrivilege,
            "Requested Bank doesn't have KYC Privilege"
        );

        //to make sure custUniqueId_ passed in the function is already a customer added to the array customerUniqueIds
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check in the request mapping for the a request on a unique customer, if bank address was anything but zero,(means it was initialized wiht a value different from declaration
        require(
            kycRequests[custUniqueId_].bankAddress == address(0),
            "A KYC Request is already pending wiht this customer"
        );

        //storing the request in kycRequest mapping mapped with the custUnique ID, with the sender as bank that requested, and response is set to default false.
        kycRequests[custUniqueId_] = KYCRequest(
            custUniqueId_,
            msg.sender,
            false
        );
        banks[msg.sender].kycCount++;

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.AddKYCRequest);

        //emit the event to store the arguments passed in the transaction logs when emitted
        emit CustomerKYCRequestAdded();
        return true;
    }

    /*
        * Name: removeKYCRequest
        * Description:This function is used to remove the kyc request from the requests list.
          If kycPermission is set to false, bank won't be allowed to remove requests for any customer.
          If a different bank than the one that initiated the request the transaction will revert
        * param1: {uint256} custUniqueId_ : the unique id of the customer for whom KYC is to be done
    */

    function removeKYCRequest(uint256 custUniqueId_) public returns (int256) {
        //check if the address of the sender is the same bank that added the request or the sender is the admin
        require(
            (kycRequests[custUniqueId_].bankAddress == msg.sender) ||
                (msg.sender == admin),
            "Requested Bank is not authorized to remove this customer as KYC is not initiated by you"
        );

        //make sure that the sender has kycPrivilege as true.
        require(
            banks[msg.sender].kycPrivilege,
            "Requested Bank doesn't have KYC Privilege"
        );

        //delete the KYCRequest from the kycRequests mapping
        delete kycRequests[custUniqueId_];

        //emit the event to store the arguments passed in the transaction logs when emitted
        emit CustomerKYCRequestRemoved();

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.RemoveKYCRequest);
        return 1;
    }

    /*
        * Name: addCustomer
        * Description:this function will add a customer to the  customer list.
          Add the customer uniqueId to customerUniqueIds array.
          Fucntion will check the sender and for duplication
        * Param1: {string memory} firstName_ : The first name of the customer applying at the bank.
        * Param2: {string memory} lastName_ : The last name of the customer applying at the bank.
        * Param3: {string memory} data_ : the data hashed for the customer to be stored in the customer struct.
        * Param4: {uint256} custUniqueId_ : the unique id of the customer that will be added to the customer list. Should be evaulated using the jordanian national number;
    */

    function addCustomer(
        string memory firstName_,
        string memory lastName_,
        string memory data_,
        uint256 custUniqueId_
    ) public {
        //make sure the admin bank is the only one allowed to add customer, or can in the future give permission to other banks
        require(
            banks[msg.sender].isAllowedToAddCustomer,
            "Requested Bank is not allowed to add customers to customer's list"
        );

        //make sure that there is no duplicates when adding customers,  by making sure that address is 0 was not added to the customersInformation mapping
        require(
            customersInformation[custUniqueId_].validatedBank == address(0),
            "Customer already exists in the customer's list"
        );

        //add the customer to the customer mapping, with the KYC Status as Pending initially and needs to be approved by Admin
        customersInformation[custUniqueId_] = Customer(
            firstName_,
            lastName_,
            data_,
            custUniqueId_,
            msg.sender,
            KycStatus.Pending
        );

        //add custUniqueId_ to the array for reference adn looping
        customerUniqueIds.push(custUniqueId_);

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.AddCustomer);

        //emit the event to store the arguments passed in the transaction logs when emitted
        emit NewCustomerCreated(custUniqueId_);
    }

    /*
        * Name: removeCustomer
        * Description: This function will remove the customer from the customer list.
          remove the customer uniqueId from array, remove the kyc request of that customer.
          Only the bank which added the customer can remove him.
        * Param1: {uint256} custUniqueId_ : the unique id of the customer that will be removed.
    */

    function removeCustomer(uint256 custUniqueId_) public returns (bool) {
        //check if the customer we want to remove has a validated bank address, if so he was initialized by a bank and found in the customerInformation mapping
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check if validatedbank for a certain customer is the same bank calling the removeCustomer function
        require(
            customersInformation[custUniqueId_].validatedBank == msg.sender,
            "Requested Bank is not authorized to remove this customer as KYC is not initiated by the requesting bank."
        );

        //delete customer data from customer list;
        delete customersInformation[custUniqueId_];

        //deletingd customer id from array using private remove function
        removeUniqueId(custUniqueId_);

        //remove the most current requests done on the deleted  customer, if it exists.
        if (kycRequests[custUniqueId_].customerUniqueId == custUniqueId_) {
            removeKYCRequest(custUniqueId_);
        }

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.RemoveCustomer);

        //emit the event to store the arguments passed in the transaction logs when emitted
        emit CustomerRemoved();
        return true;
    }

    /*
     * Name: modifyCustomer
     * Description: this function will modify the customer struct data members from the customer list.
     * Param1: {uint256} custUniqueId_ : the unique id of the customer that will be modified.
     * Param2: {string memory} data_ : the new data that will overwrite the old data.
     */

    function modifyCustomer(uint256 custUniqueId_, string memory data_)
        public
        returns (bool)
    {
        //check if the customer we want to Modify has a validated bank address and exists, if so he was initialized by a bank and found in the customerInformation mapping
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check if validatedbank for a certain customer is the same bank calling the Modify function
        require(
            customersInformation[custUniqueId_].validatedBank == msg.sender,
            "Requested Bank is not authorized to Modify this customer as Customer was not initiated by the requesting bank."
        );

        //remove any requests with outdated data;
        removeKYCRequest(custUniqueId_);

        //update customer data with new data;
        customersInformation[custUniqueId_].data = data_;

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.ModifyCustomer);

        //emit the event to store the arguments passed in the transaction logs when emitted
        emit CustomerInfoModified();
    }

    /*  
        * Name: viewCustomerData
        * Description: This function is used to fetch cutomer data from the smart contracts 
          and allows a bank to view details
        * Param1: {uint256} custUniqueId_ : the unique id of the customer's details that will be viewed.
    */

    function viewCustomerData(uint256 custUniqueId_)
        public
        returns (string memory)
    {
        //check if the customer has a validated bank address and exists, if so he was initialized by a bank and found in the customerInformation mapping, to be able to view his data
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check that the caller is a bank regestered and has kycAccess.
        require(
            banks[msg.sender].ethAddress == address(msg.sender),
            "Requested Bank doesn't have KYC Privilege"
        );

        //audit this action by inserting the sender and the correct request
        auditBankActions(msg.sender, BankActions.ViewCustomer);

        return (customersInformation[custUniqueId_].data);
    }

    /*  
        * Name: getCustomerKycStatus
        * Description: this function is used to fetch cutomer KYC Status from the smart contracts
          and allows a bank to view the current status.
        * Param1: {uint256} custUniqueId_ : the unique id of the customer's details that will be viewed.
    */

    function getCustomerKycStatus(uint256 custUniqueId_)
        public
        view
        returns (string memory)
    {
        //check if the customer has a validated bank address and exists, if so he was initialized by a bank and found in the customerInformation mapping, to be able to view his data
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check that the caller is a bank regestered and has kycAccess.
        require(
            banks[msg.sender].ethAddress == address(msg.sender),
            "Requested Bank doesn't have KYC Privilege"
        );

        //audit this action by inserting the sender and the correct request
        //auditBankActions(msg.sender, BankActions.ViewCustomer);

        //evaluating the status through ENUM to string conversion to return a string
        if (
            getIntFromKycEnum(customersInformation[custUniqueId_].status) == 0
        ) {
            return "Pending";
        } else if (
            getIntFromKycEnum(customersInformation[custUniqueId_].status) == 1
        ) {
            return "Approved";
        } else {
            return "Declined";
        }
    }

    /*
     * Name: setCustomerKycStatus
     * Description: this function will set the kyc status of a customer
     * Param1: {uint256} custUniqueId_ : the unique id of the customer's kyc that will be set.
     * Param2: {int} kycInt_ : the int value referncing the ENUM value initiated in the contract.
     */

    //onlyAdmin modifier specifies that only the address that deployed the contract can call this function, in this case super Admin 
    function setCustomerKycStatus(uint256 custUniqueId_, int256 kycInt_)
        public
        onlyAdmin
    {
        //check if the customer has a validated bank address and exists, if so he was initialized by a bank and found in the customerInformation mapping, to be able to view his data
        require(
            customersInformation[custUniqueId_].validatedBank != address(0),
            "Requested Customer is not found/Not exist in Customers list"
        );

        //check that kyc int passed into the function is valid
        require(kycInt_ == 1 || kycInt_ == 2, "KycStatus Inputed is not valid");

        if (kycInt_ == 1) {
            customersInformation[custUniqueId_].status = KycStatus.Approved;
            auditBankActions(msg.sender, BankActions.ApproveKYC);
        } else {
            customersInformation[custUniqueId_].status = KycStatus.Declined;
            auditBankActions(msg.sender, BankActions.DeclineKYC);
        }

        //if admin checks and approves the new kyc status, he has responded and hence the response flag on the request is changed to true;
        kycRequests[custUniqueId_].adminResponse = true;
    }

     //------------------GETTERS-------------------------------------
    //getter functions to be called in web3.js    
    function getCustomerInformation(uint256 customerIndex)
        public
        view
        returns (
            uint256,
            string memory,
            string memory,
            string memory,
            address,
            string memory
        )
    {
        uint256 tempCustId = customerUniqueIds[customerIndex];
        string memory tempKycStatus = getCustomerKycStatus(tempCustId);
        return (
            customersInformation[tempCustId].uniqueId,
            customersInformation[tempCustId].firstName,
            customersInformation[tempCustId].lastName,
            customersInformation[tempCustId].data,
            customersInformation[tempCustId].validatedBank,
            tempKycStatus
        );
    }

    function getBanksInformation(uint256 bankIndex)
        public
        view
        returns (
            string memory,
            string memory,
            uint256,
            address,
            bool,
            bool
        )
    {
        address tempBankAddress = bankAddressess[bankIndex];
        return (
            banks[tempBankAddress].name,
            banks[tempBankAddress].regNumber,
            banks[tempBankAddress].kycCount,
            banks[tempBankAddress].ethAddress,
            banks[tempBankAddress].isAllowedToAddCustomer,
            banks[tempBankAddress].kycPrivilege
        );
    }

    function getPendingKycRequests(uint256 customerIndex)
        public
        view
        returns (uint256, address)
    {
        uint256 tempCustId = customerUniqueIds[customerIndex];
        if (kycRequests[tempCustId].bankAddress != address(0)) {
            if (
                kycRequests[tempCustId].adminResponse == false &&
                customersInformation[tempCustId].status == KycStatus.Pending
            ) {
                return (
                    kycRequests[tempCustId].customerUniqueId,
                    kycRequests[tempCustId].bankAddress
                );
            }
        }
    }

    

    function getBankCount() public view returns (uint256) {
        return bankAddressess.length;
    }

    function getCustomerCount() public view returns (uint256) {
        return customerUniqueIds.length;
    }

    function getTotalPendingKycRequests() public view returns (uint256) {
        uint256 kycCount = 0;
        for (uint256 i = 0; i < customerUniqueIds.length; i++) {
            if (kycRequests[customerUniqueIds[i]].bankAddress != address(0)) {
                kycCount++;
            }
        }
        return kycCount;
    }

    function getAdmin() public view returns (address) {
        return admin;
    }

    //------------------------------Functions Regarding Banks on the network------------------------------------------

    //addBank function is overloaded as Solidity does not support default parameters

    /*  
        * Name: addBank - with all parameters passed
        * Description: This function is Overloaded used by the admin to add a bank to the KYC Contract.
          You need to verify if the user trying to call this function is admin or not.
        * Param1: {string memory} bankName_ : the unique bank name.
        * Param2: {string memory} bankRegNumber_: the unique bankRegNumber_.
        * Param3: {address} ethAddress_:THe address of the new added bank.
        * Param4: {bool} isAllowedToAddCustomer: bool value set by admin to give permission to other banks to add/remove customers.
        * Param5: {bool} kycPrivilege : bool value set by ad min to give permission to othe banks to request and view customer kyc status.
    */

    //onlyAdmin modifier specifies that only the address that deployed the contract can call this function, in this case super Admin 
    function addBank(
        string memory bankName_,
        string memory bankRegNumber_,
        address ethAddress_,
        bool isAllowedToAddCustomer_,
        bool kycPrivilege_
    ) public onlyAdmin {
        //check if a bank already exist with the same name
        for (uint256 i = 0; i < bankAddressess.length; i++) {
            require(
                !areBothStringSame(banks[bankAddressess[i]].name, bankName_),
                "A Bank already exists with the same name"
            );
        }

        //check if a bank already exists with the same registration number
        require(
            banksRegestrationNumberMapping[bankRegNumber_].ethAddress ==
                address(0),
            "A Bank already exists with the smae registration number"
        );

        //check that the ethAddress is unique and not duplicated
        for (uint256 i = 0; i < bankAddressess.length; i++) {
            require(
                ethAddress_ != banks[bankAddressess[i]].ethAddress,
                "A Bank already exists with the same Eth address"
            );
        }

        //save the bank in the banks mapping with defualt options false for kycPrivilege, and IsAllowedToAddCustomer;
        banks[ethAddress_] = Bank(
            bankName_,
            bankRegNumber_,
            0,
            ethAddress_,
            isAllowedToAddCustomer_,
            kycPrivilege_
        );

        //save the bank in the banks regestration number mapping by using bank_name as key
        banksRegestrationNumberMapping[bankRegNumber_] = Bank(
            bankName_,
            bankRegNumber_,
            0,
            ethAddress_,
            false,
            false
        );

        //add the address to the bankAddresses array
        bankAddressess.push(ethAddress_);

        emit NewBankCreated();
    }

    /*  
        * Name: addBank - with DEFUALT VALUES
        * Description: This function is overloaded used by the admin to add a bank to the KYC Contract.
          You need to verify if the user trying to call this function is admin or not.
        * Param1: {string memory} bankName_ : the unique bank name.
        * Param2: {string memory} bankRegNumber_: the unique bankRegNumber_.
        * Param3: {address} ethAddress_:THe address of the new added bank.
    */

    //onlyAdmin modifier specifies that only the address that deployed the contract can call this function, in this case super Admin 
    function addBank(
        string memory bankName_,
        string memory bankRegNumber_,
        address ethAddress_
    ) public onlyAdmin {
        //check if a bank already exist with the same name
        for (uint256 i = 0; i < bankAddressess.length; i++) {
            require(
                !areBothStringSame(banks[bankAddressess[i]].name, bankName_),
                "A Bank already exists with the same name"
            );
        }

        //check if a bank already exists with the same registration number
        require(
            banksRegestrationNumberMapping[bankRegNumber_].ethAddress ==
                address(0),
            "A Bank already exists with the smae registration number"
        );

        //check that the ethAddress is unique and not duplicated
        for (uint256 i = 0; i < bankAddressess.length; i++) {
            require(
                ethAddress_ != banks[bankAddressess[i]].ethAddress,
                "A Bank already exists with the same Eth address"
            );
        }

        //save the bank in the banks mapping with defualt options false for kycPrivilege, and IsAllowedToAddCustomer;
        banks[ethAddress_] = Bank(
            bankName_,
            bankRegNumber_,
            0,
            ethAddress_,
            false,
            false
        );

        //save the bank in the banks regestration number mapping by using bank_name as key
        banksRegestrationNumberMapping[bankRegNumber_] = Bank(
            bankName_,
            bankRegNumber_,
            0,
            ethAddress_,
            false,
            false
        );

        //add the address to the bankAddresses array
        bankAddressess.push(ethAddress_);

        emit NewBankCreated();
    }

    /*
        * Name: removeBank
        * Description: this function will remove the bank from the network and will never get
          access to view blocks or interact with the private blockchain.
        * Param1: {address} ethAddress_ : The ethereum address of the bank the admin wants to remove.
    */

    function removeBank(address ethAddress_) public onlyAdmin {
        //check if the bank exists in the first palce, in the banks list
        require(banks[ethAddress_].ethAddress != address(0), "Bank not found");

        //QUESTION: How to optimise this function?#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_##_#_######

        //check if any customer has a kyc request done by the bank that is being deleted and remove the kycRequest that is still pending a response from the admin
        for (uint256 i = 0; i < customerUniqueIds.length; i++) {
            if (
                kycRequests[customerUniqueIds[i]].bankAddress == ethAddress_ &&
                kycRequests[customerUniqueIds[i]].adminResponse == false
            ) {
                removeKYCRequest(customerUniqueIds[i]);
            }
        }

        //deleting the bank struct form banksRegNumber mappping
        delete banksRegestrationNumberMapping[banks[ethAddress_].regNumber];

        //delete teh bank struct from teh banks mapping
        delete banks[ethAddress_];

        //delete teh bank address forn bankAddresses array
        removeBankAddress(ethAddress_);
    }

    //--internal properties can be accessed from child contracts (but not from external contracts).
    //-- private properties can't be accessed even from child contracts.
    //--Private functions can only be called from inside the contract,
    //even the inherited contracts can't call them.

    /*
     * Name: auditBankActions
     * Description: -internal private function to track all actions done by any bank.
     * Param1: {address} changesDoneBy : Ethereum address of the bank who made the change
     * Param2: {BankActions} bankAction : The ENUM value of action done by the bank.
     */
    function auditBankActions(address changesDoneBy, BankActions bankAction_)
        private
    {
        //now is a shorthand reference to the current block's timestamp
        int256 bankActionValue = getIntFromBankEnum(bankAction_);
        bankActionsAudit[changesDoneBy][bankActionValue] = block.timestamp;
    }

    /*
        * Name: getIntFromBankEnum
        * Description: private function to convert between Enum and int and return an int.
          Used for corret data conversion and data type compatibility--external conversion
        * Param1: {BankActions} bankAction_ : The ENUM value of action done by the bank.
    */

    function getIntFromBankEnum(BankActions bankAction_)
        private
        pure
        returns (int256)
    {
        return int256(bankAction_);
    }

    /*
        * Name: getIntFromKycEnum
        * Description: private function to convert between Enum and int and return an int.
          Used for corret data conversion and data type compatibility--external conversion.
        * Param1: {KycStatus} status_ : The ENUM value of action done by the bank.
    */

    function getIntFromKycEnum(KycStatus status_)
        private
        pure
        returns (int256)
    {
        return int256(status_);
    }

    /*
        * Name: removeUniqueId
        * Description: private function that takes the unique id of the customer,
          replaces the the customer id at the last index with the customer id we want to delete
          and pops the last element in the array 'customerUniqueIds'.
        * param1: {uint256} uniqueId_ : the customer unique id
    */

    function removeUniqueId(uint256 uniqueId_) private {
        for (uint256 index = 0; index < customerUniqueIds.length; index++) {
            if (uniqueId_ == customerUniqueIds[index]) {
                customerUniqueIds[index] = customerUniqueIds[
                    customerUniqueIds.length - 1
                ];
                customerUniqueIds.pop();
                break;
            }
        }
    }

    /*
        * Name: removeBankAddress
        * Description: private function that takes the unique address of the bank,
          replaces the the bank address at the last index with the bank address we want to delete
          and pops the last element in the array 'bankAddressess'.
        * param1: {address} ethAddress_ : The unique Etheruem address of the bank
    */

    function removeBankAddress(address ethAddress_) private {
        for (uint256 index = 0; index < bankAddressess.length; index++) {
            if (ethAddress_ == bankAddressess[index]) {
                bankAddressess[index] = bankAddressess[
                    bankAddressess.length - 1
                ];
                bankAddressess.pop();
                break;
            }
        }
    }

    /*
        * Name: areBothStringSame
        * Description: private his is an internal function is verify equality of strings.
          it checks if begins by checking if the lenght are equal,
          if not equal they are not the same
          else if they are equal we will hash both strings using keccak256 algorithm
          to check if both string give same output
        * Param1: {string memory} a_ : 1st string.
        * Param2: {string memory} b_ : 2nd string.
    */

    function areBothStringSame(string memory a_, string memory b_)
        private
        pure
        returns (bool)
    {
        if (bytes(a_).length != bytes(b_).length) {
            return false;
        } else {
            return keccak256(bytes(a_)) == keccak256(bytes(b_));
        }
    }

    //end of contract scope
}
