import SotoDynamoDB

public enum RepositoryFactory {
    public typealias UserRepoParams = (
        db: DynamoDB,
        tableName: String,
        eventLoop: any EventLoop,
        logger: Logger
    )
    
    public static var makeUserRepository: (UserRepoParams) -> any UserRepository = {
        DynamoUserRepository(
            db: $0.db,
            tableName: $0.tableName,
            eventLoop: $0.eventLoop,
            logger: $0.logger
        )
    }
    
    public typealias AutoPingsRepoParams = (awsClient: AWSClient, logger: Logger)
    
    public static var makeAutoPingsRepository: (AutoPingsRepoParams) -> any AutoPingsRepository = {
        S3AutoPingsRepository(awsClient: $0.awsClient, logger: $0.logger)
    }

    public typealias HelpsRepoParams = (awsClient: AWSClient, logger: Logger)

    public static var makeHelpsRepository: (HelpsRepoParams) -> any HelpsRepository = {
        S3HelpsRepository(awsClient: $0.awsClient, logger: $0.logger)
    }
}
