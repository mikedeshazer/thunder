pragma solidity >=0.4.21 <0.7.0;

contract Wallet {
  struct Repo {
      bytes32 id;
      string name;
      string owner;
  }

  struct Issue {
      bytes32 id;
      uint64 number;
      address creator;
      uint256 bounty;
  }
  
  struct PullRequest {
      bytes32 id;
      uint64 issueNumber;
      uint64 number;
      address creator;
      string creatorName;
      bool isClosed;
  }

  mapping(address => Repo[]) repoOwner;
  mapping(bytes32 => Issue[]) repoIssues;
  mapping(bytes32 => uint256) issueBounty;
  mapping(bytes32 => bool) hasBountyOption;
  mapping(bytes32 => address) pullRequestIdCreator;
  mapping(bytes32 => address) repoIdOwner;
  mapping(bytes32 => bytes32) issueIdRepoId;
  mapping(bytes32 => mapping(bytes32 => mapping(address => PullRequest))) repoPullRequests;
  mapping(bytes32 => mapping(bytes32 => PullRequest[])) repoPullRequestsArr;
  
  event NewRepoEvent(string repoOwner, string repoName, bytes32 repoId);
  event NewIssueEvent(string repoOwner, string repoName, bytes32 issueId, uint256 bounty);
  event NewPullRequestEvent(address pullRequestCreator, string repoName, uint64 issueId);

  constructor() public {}
  
  modifier onlyRepoOwner(
      string memory _repoOwner,
      string memory _repoName
  )
  {
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      require(msg.sender == repoIdOwner[repoId], "onlyRepoOwner -> This function is callable only by the repo owner");
      _;
  }

  function newRepo (
      string memory _repoOwner,
      string memory _repoName
  )
      public
      returns (bool)
  {
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      repoOwner[msg.sender].push(Repo(repoId, _repoName, _repoOwner));
      hasBountyOption[repoId] = true;
      repoIdOwner[repoId] = msg.sender;
      emit NewRepoEvent(_repoOwner, _repoName, repoId);
      return true;
  }

  function newIssue (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber
  )
      public
      payable
      returns (bool)
  {
      require(msg.value > 0, "newIssue -> Issue bounty must be greater than 0");
      
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      
      require(issueIdRepoId[issueId] == 0, "newIssue -> Issue already existing");
      
      repoIssues[repoId].push(Issue(issueId, _issueNumber, msg.sender, msg.value));
      issueBounty[issueId] = msg.value;
      issueIdRepoId[issueId] = repoId;
      emit NewIssueEvent(_repoOwner, _repoName, issueId, msg.value);
      return true;
  }

  function getIssuePrice (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber
  )
      public
      view
      returns (uint256)
  {
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      return issueBounty[issueId];
  }
  
  function hasRepoBountyOption (
      string memory _repoOwner,
      string memory _repoName
  )   
      public
      view
      returns (bool)
  {
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      return hasBountyOption[repoId];
  }
  
  /**
   * User can do only a PR on an issue (for now)
   * */
  function newPullRequest (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber,
      uint64 _pullRequestNumber,
      string memory _creatorName
  )
      public
      returns (bool)
  {
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      require(issueIdRepoId[issueId] == repoId, "newPullRequest -> Issue not existing");
      
      bytes32 pullRequestId = keccak256(abi.encodePacked(_repoName, _repoOwner, _issueNumber, _pullRequestNumber, msg.sender));
      require(pullRequestIdCreator[pullRequestId] != msg.sender, "msg.sender has already done a PR on this issue");
      
      PullRequest memory pullRequest = PullRequest(pullRequestId, _issueNumber, _pullRequestNumber, msg.sender, _creatorName, false);
      repoPullRequests[repoId][issueId][msg.sender] = pullRequest;
      repoPullRequestsArr[repoId][issueId].push(pullRequest);
      pullRequestIdCreator[pullRequestId] = msg.sender;
      emit NewPullRequestEvent(msg.sender, _repoName, _issueNumber);
      return true;
  }
  
  function getNumberOfPullRequests (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber
  )
      public
      view
      returns (uint256)
  {
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      return repoPullRequestsArr[repoId][issueId].length;
  }
  
  function getPullRequest (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber,
      uint256 _index
  ) 
      public
      view
      returns (address, string memory)
  {
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      PullRequest memory pullRequest = repoPullRequestsArr[repoId][issueId][_index];
      return (pullRequest.creator, pullRequest.creatorName);
  }
  
  /**
   * _receiver taken from selection! -> attacker could make a fake PR 
   * (to pass require(pullRequestIdCreator[pullRequestId] == _receiver, "acceptPullRequest -> _receiver didn't perform a pull request")),
   * infect the selection in order to change the address and take the money! (very unlikely)
   *  
   **/
  function acceptPullRequest (
      string memory _repoOwner,
      string memory _repoName,
      uint64 _issueNumber,
      uint64 _pullRequestNumber,
      address _receiver
  )
      public
      onlyRepoOwner(_repoOwner, _repoName)
      returns (bool)
  {
      //receiver has a PR on this issueId
      //repoExissts
      bytes32 issueId = keccak256(abi.encodePacked(_issueNumber, _repoName, _repoOwner));
      bytes32 repoId = keccak256(abi.encodePacked(_repoName, _repoOwner));
      require(issueIdRepoId[issueId] == repoId, "acceptPullRequest -> Issue not existing");
      
      bytes32 pullRequestId = keccak256(abi.encodePacked(_repoName, _repoOwner, _issueNumber, _pullRequestNumber, _receiver));
      require(pullRequestIdCreator[pullRequestId] == _receiver, "acceptPullRequest -> _receiver didn't perform a pull request");
      
      PullRequest storage pullRequest = repoPullRequests[repoId][issueId][_receiver];
      require(pullRequest.isClosed == false, "acceptPullRequest -> Pull request already closed");
      
      //get issue price of this PullRequest
      uint256 bounty = issueBounty[issueId];
      (bool success, ) = _receiver.call.value(bounty)("");
      require(success == true, "acceptPullRequest -> Error during bounty transfering");
      
      pullRequest.isClosed = true;
      
      return true;
  }
}
